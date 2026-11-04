import Foundation

enum ResolveError: LocalizedError {
    case ytdlpNotFound
    case ytdlpFailed(String)
    case noManifest
    case rateLimited
    case notLive
    case pageUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound: return "yt-dlp not found (brew install yt-dlp)"
        case .ytdlpFailed(let msg): return msg.isEmpty ? "yt-dlp failed" : msg
        case .noManifest: return "No HLS stream (channel offline?)"
        case .rateLimited: return "Too many requests; backing off"
        case .notLive: return "Not live right now"
        case .pageUnreadable(let msg): return msg
        }
    }
}

/// Returns the master HLS manifest for a live channel: via yt-dlp for YouTube,
/// straight from the site for Rumble and Kick. AVPlayer plays the master
/// manifest directly, picking video + audio itself.
enum StreamResolver {

    private static let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin", "/usr/bin",
    ]

    private static var ytdlp: String? {
        searchPaths.map { $0 + "/yt-dlp" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func resolve(_ channel: Channel) async throws -> URL {
        switch channel.site {
        case .youtube:
            let result = try await run(["-j", "--no-warnings", channel.liveURL.absoluteString])
            guard result.status == 0 else { throw result.error }
            return try manifestURL(fromInfoJSON: result.stdout)

        case .rumble:
            return try await RumbleResolver.resolve(channel)

        case .kick:
            return try await KickResolver.resolve(channel)
        }
    }

    private struct RunResult {
        let stdout: Data
        let stderr: Data
        let status: Int32

        /// The last line yt-dlp wrote to stderr, as an error.
        var error: ResolveError {
            let text = String(decoding: stderr, as: UTF8.self)
            if text.contains("HTTP Error 429") { return .rateLimited }
            let last = text.split(separator: "\n").last.map(String.init) ?? ""
            return .ytdlpFailed(last.replacingOccurrences(of: "ERROR: ", with: ""))
        }
    }

    private static func run(_ arguments: [String]) async throws -> RunResult {
        guard let tool = ytdlp else { throw ResolveError.ytdlpNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments

        // Make sure yt-dlp can find its helpers (deno, ffmpeg) from a GUI launch.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await Task.detached {
            try process.run()
            let d = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return RunResult(stdout: d, stderr: e, status: process.terminationStatus)
        }.value
    }

    /// Pull the first `manifest_url` out of yt-dlp's info JSON.
    /// For YouTube live that's the master .m3u8 containing every variant.
    private static func manifestURL(fromInfoJSON data: Data) throws -> URL {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let formats = json["formats"] as? [[String: Any]]
        else { throw ResolveError.noManifest }

        for format in formats {
            if let proto = format["protocol"] as? String, proto.hasPrefix("m3u8"),
               let manifest = format["manifest_url"] as? String,
               let url = URL(string: manifest) {
                return url
            }
        }
        throw ResolveError.noManifest
    }
}
