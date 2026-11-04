import Foundation

/// Finds what a Rumble channel is streaming right now with a single request.
///
/// A channel's livestreams page (`rumble.com/c/<name>/livestreams`) embeds its
/// newest streams as JSON inside `<rum-videos-grid>`. Each entry says whether
/// it's live and carries its HLS master manifest, so there's no need for
/// yt-dlp here. (yt-dlp's Rumble channel extractor reads every page of the
/// channel's archive first, which trips Rumble's rate limit.)
enum RumbleResolver {

    static func resolve(_ channel: Channel) async throws -> URL {
        var request = URLRequest(url: channel.liveURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 429: throw ResolveError.rateLimited
        case 404: throw ResolveError.pageUnreadable("No such Rumble channel")
        case let code: throw ResolveError.pageUnreadable("Rumble returned HTTP \(code)")
        }

        let page = String(decoding: data, as: UTF8.self)
        guard let json = gridJSON(in: page) else {
            throw ResolveError.pageUnreadable("Couldn't read the Rumble channel page")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let grid = try decoder.decode(Grid.self, from: Data(json.utf8))

        guard let live = grid.items.first(where: \.isLive) else { throw ResolveError.notLive }
        let variants = live.videos ?? []
        guard
            let manifest = (variants.first { $0.type == "hls" } ?? variants.first { $0.url.contains(".m3u8") }),
            let url = URL(string: manifest.url, relativeTo: URL(string: "https://rumble.com"))
        else { throw ResolveError.noManifest }
        return url.absoluteURL
    }

    /// The JSON in the `<script type="application/json">` inside `<rum-videos-grid>`.
    private static func gridJSON(in page: String) -> String? {
        guard
            let grid = page.range(of: "<rum-videos-grid"),
            let open = page.range(of: "<script type=\"application/json\">", range: grid.upperBound..<page.endIndex),
            let close = page.range(of: "</script>", range: open.upperBound..<page.endIndex)
        else { return nil }
        return String(page[open.upperBound..<close.lowerBound])
    }

    private struct Grid: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let live: Bool?
        /// 2 while the stream is on air.
        let livestreamStatus: Int?
        let videos: [Variant]?

        var isLive: Bool { live == true || livestreamStatus == 2 }
    }

    private struct Variant: Decodable {
        let url: String
        let type: String?
    }
}
