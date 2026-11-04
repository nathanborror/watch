import Foundation

/// A live channel. On YouTube the id is an @handle (without the @) or a UC…
/// channel ID; on Rumble it's `rumble:<name>`, the part after `rumble.com/c/`;
/// on Kick it's `kick:<name>`, the part after `kick.com/`.
/// `name` is an optional friendly label shown on the tile.
struct Channel: Identifiable, Hashable {
    let id: String
    var name: String?

    enum Site {
        case youtube
        case rumble
        case kick

        /// How long to wait before the first retry. Rumble rate-limits hard,
        /// so it gets more room.
        var retryDelay: TimeInterval {
            switch self {
            case .youtube: return 30
            case .rumble: return 90
            case .kick: return 60
            }
        }

        /// The id prefix that marks a channel on this site. YouTube has none.
        var prefix: String {
            switch self {
            case .youtube: return ""
            case .rumble: return "rumble:"
            case .kick: return "kick:"
            }
        }
    }

    private static let prefixedSites: [Site] = [.rumble, .kick]

    var site: Site {
        Self.prefixedSites.first { id.hasPrefix($0.prefix) } ?? .youtube
    }

    /// The id without its site prefix.
    private var bareID: String { String(id.dropFirst(site.prefix.count)) }

    /// Where the resolver starts. On YouTube this page resolves straight to
    /// whatever the channel is streaming now. Rumble has no such page, so this
    /// is the channel's list of livestreams, and the resolver picks out the
    /// one that's actually live. On Kick it's the channel's API record, which
    /// says whether it's live and where the stream is.
    var liveURL: URL {
        switch site {
        case .rumble:
            return URL(string: "https://rumble.com/c/\(bareID)/livestreams")!
        case .kick:
            return URL(string: "https://kick.com/api/v2/channels/\(bareID)")!
        case .youtube where id.hasPrefix("UC"):
            return URL(string: "https://www.youtube.com/channel/\(id)/live")!
        case .youtube:
            return URL(string: "https://www.youtube.com/@\(id)/live")!
        }
    }

    /// The friendly name if there is one, otherwise the id.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return idLabel
    }

    var idLabel: String {
        switch site {
        case .rumble: return "\(bareID) · Rumble"
        case .kick: return "\(bareID) · Kick"
        case .youtube: return id.hasPrefix("UC") ? id : "@\(id)"
        }
    }

    init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }

    /// Accepts whatever you'd paste: `NASA`, `@NASA`, a `UC…` ID,
    /// `rumble:Name`, `kick:name`, or a youtube.com / rumble.com / kick.com
    /// channel URL.
    /// Returns nil for anything that isn't a channel (a video link, say).
    init?(input: String, name: String? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let host = url.host?.lowercased() {
            let parts = url.pathComponents.filter { $0 != "/" }
            if host.hasSuffix("rumble.com") {
                guard parts.count >= 2, parts[0] == "c" else { return nil }
                self.init(id: Site.rumble.prefix + parts[1], name: name)
                return
            }
            if host.hasSuffix("kick.com") {
                // kick.com/<name>; anything deeper is a video or clip.
                guard parts.count == 1 else { return nil }
                self.init(id: Site.kick.prefix + parts[0].lowercased(), name: name)
                return
            }
            if host.hasSuffix("youtube.com") {
                if let first = parts.first, first.hasPrefix("@") {
                    self.init(id: String(first.dropFirst()), name: name)
                    return
                }
                guard parts.count >= 2, parts[0] == "channel" else { return nil }
                self.init(id: parts[1], name: name)
                return
            }
            return nil
        }

        var id = text
        if let site = Self.prefixedSites.first(where: { text.lowercased().hasPrefix($0.prefix) }) {
            let rest = id.dropFirst(site.prefix.count)
            guard !rest.isEmpty else { return nil }
            // Kick names are lowercase in its API; Rumble's keep their case.
            id = site.prefix + (site == .kick ? rest.lowercased() : String(rest))
        } else if id.hasPrefix("@") {
            id.removeFirst()
        }
        guard !id.isEmpty, !id.contains(where: { $0.isWhitespace || $0 == "/" })
        else { return nil }
        self.init(id: id, name: name)
    }

    /// The channels a first-time install starts with: one per tile in the
    /// default 2×2 grid. After that, the list belongs to the user.
    static let defaults: [Channel] = [
        Channel(id: "SkyNews", name: "Sky News"),
        Channel(id: "NBCNews", name: "NBC News"),
        Channel(id: "PBSNewsHour", name: "PBS NewsHour"),
        Channel(id: "CNN", name: "CNN"),
        Channel(id: "mtsituation", name: "MTS"),
        Channel(id: "aljazeeraenglish", name: "Aljazeera"),
        Channel(id: "rumble:RTNews", name: "RT"),
        Channel(id: "breakingpoints", name: "Breaking Points"),
        Channel(id: "BBCNews", name: "BBC News"),
    ]
}

// MARK: - JSON

/// In channels.json each entry is either `{"id": "...", "name": "..."}` or
/// just a string in any form `init(input:)` accepts, so a long list can be
/// pasted in by hand.
extension Channel: Codable {
    private enum CodingKeys: String, CodingKey { case id, name }

    struct InvalidEntry: Error {}

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard let channel = Channel(input: text) else { throw InvalidEntry() }
            self = channel
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .id)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        guard let channel = Channel(input: raw, name: name) else { throw InvalidEntry() }
        self = channel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let name, !name.isEmpty {
            try container.encode(name, forKey: .name)
        }
    }
}
