import Foundation

/// Finds what a Kick channel is streaming right now with a single request.
///
/// `kick.com/api/v2/channels/<name>` returns the channel's record:
/// `livestream` is null (or `is_live` false) when it's offline, and
/// `playback_url` is the HLS master manifest. That URL carries a token that
/// expires after a few minutes, but it's only checked when playback starts;
/// a tile that loses playback re-resolves and gets a fresh one.
enum KickResolver {

    static func resolve(_ channel: Channel) async throws -> URL {
        var request = URLRequest(url: channel.liveURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 429: throw ResolveError.rateLimited
        case 404: throw ResolveError.pageUnreadable("No such Kick channel")
        case 403: throw ResolveError.pageUnreadable("Kick blocked the request")
        case let code: throw ResolveError.pageUnreadable("Kick returned HTTP \(code)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let record = try? decoder.decode(ChannelRecord.self, from: data) else {
            throw ResolveError.pageUnreadable("Couldn't read Kick's reply")
        }
        guard record.livestream?.isLive == true else { throw ResolveError.notLive }
        guard let manifest = record.playbackUrl, let url = URL(string: manifest) else {
            throw ResolveError.noManifest
        }
        return url
    }

    private struct ChannelRecord: Decodable {
        let playbackUrl: String?
        let livestream: Livestream?
    }

    private struct Livestream: Decodable {
        let isLive: Bool?
    }
}
