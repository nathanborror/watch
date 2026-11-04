import Combine
import Foundation

/// The grid: how many tiles are showing, which channel each tile position
/// holds, which tile has audio, and how far it's zoomed in.
///
/// There are always nine positions. The tile count decides how many are
/// visible; hidden positions keep their channel, so going from 9 to 4 and back
/// restores what was there. Only visible positions have a running `TileModel`.
@MainActor
final class GridModel: ObservableObject {
    enum TileCount: Int, CaseIterable, Identifiable {
        case four = 4, six = 6, nine = 9
        var id: Int { rawValue }
    }

    static let positionCount = 9

    let library: ChannelLibrary

    @Published private(set) var tileCount: TileCount
    /// The channel id at each of the nine positions.
    @Published private(set) var slots: [String?]
    /// Running tiles, keyed by position. Only visible positions have one.
    @Published private(set) var tiles: [Int: TileModel] = [:]
    @Published private(set) var focused: Int?
    @Published private(set) var zoom: Zoom = .grid
    /// How many columns the window currently fits; the view reports it.
    @Published private(set) var columns = 2

    var layout: GridLayout {
        GridLayout(count: tileCount.rawValue, columns: columns, zoom: zoom)
    }

    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let tileCount = "tileCount"
        static let slots = "slots"
    }

    init(library: ChannelLibrary) {
        self.library = library

        let defaults = UserDefaults.standard
        tileCount = TileCount(rawValue: defaults.integer(forKey: Keys.tileCount)) ?? .four
        // Property lists can't hold nil, so empty positions are saved as "".
        let saved = defaults.stringArray(forKey: Keys.slots) ?? []
        slots = (0..<Self.positionCount).map { i in
            i < saved.count && !saved[i].isEmpty ? saved[i] : nil
        }

        apply(channels: library.channels)
        focus(0)

        // @Published fires before the value changes, so use the new value it
        // hands us rather than reading library.channels.
        library.$channels
            .dropFirst()
            .sink { [weak self] channels in self?.apply(channels: channels) }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Puts a channel at a position. If it's already at another position, the
    /// two swap, and if both are on screen they keep playing without reloading.
    func assign(_ channelID: String, to position: Int) {
        if let other = slots.firstIndex(of: channelID) {
            guard other != position else { return }
            slots.swapAt(position, other)
            let moving = tiles[position]
            tiles[position] = tiles[other]
            tiles[other] = moving
        } else {
            slots[position] = channelID
        }
        syncTiles()
        save()
    }

    func setTileCount(_ count: TileCount) {
        guard count != tileCount else { return }
        tileCount = count
        zoom = .grid
        if let focused, focused >= count.rawValue { self.focused = nil }
        fillEmptySlots(from: library.channels)
        syncTiles()
        save()
    }

    /// Gives a tile the audio. If it's hidden behind a zoomed-in tile, it
    /// takes over the zoom instead, so number keys flip channels when zoomed.
    func focus(_ position: Int?) {
        if let position, zoom != .grid, layout.visibleCells[position] == nil {
            switch layout.zoom {
            case .expanded: zoom = .expanded(position)
            case .full: zoom = .full(position)
            case .grid: break
            }
            applyVisibility()
        }
        focused = position
        applyMute()
    }

    // MARK: - Zoom

    /// One step in on a tile (default: the one with audio): grid → expanded
    /// (a 2×2 block) → full. With four tiles a 2×2 block is the whole grid,
    /// so it goes straight to full. Zooming in on a tile also gives it audio.
    func zoomIn(on position: Int? = nil) {
        guard let position = position ?? focused ?? (tiles.isEmpty ? nil : 0) else { return }
        switch layout.zoom {
        case .grid:
            zoom = .expanded(position)
        case .expanded(let target):
            zoom = target == position ? .full(position) : .expanded(position)
        case .full:
            zoom = .full(position)
        }
        focused = position
        applyMute()
        applyVisibility()
    }

    /// One step out: full → expanded → grid.
    func zoomOut() {
        switch layout.zoom {
        case .grid: return
        case .expanded: zoom = .grid
        case .full(let target): zoom = layout.blockFillsGrid ? .grid : .expanded(target)
        }
        applyVisibility()
    }

    func showAll() {
        zoom = .grid
        applyVisibility()
    }

    func setColumns(_ count: Int) {
        guard count != columns else { return }
        columns = count
        applyVisibility()
    }

    func reloadAll() {
        tiles.values.forEach { $0.load() }
    }

    // MARK: - Keeping tiles in step

    /// Called at launch and whenever the channel list changes.
    private func apply(channels: [Channel]) {
        let known = Set(channels.map(\.id))
        for i in slots.indices where slots[i].map({ !known.contains($0) }) ?? false {
            slots[i] = nil
        }
        fillEmptySlots(from: channels)
        syncTiles(channels: channels)
        save()
    }

    /// Gives each empty visible position the next channel in the list that
    /// isn't already at any position.
    private func fillEmptySlots(from channels: [Channel]) {
        var unused = channels.map(\.id).filter { !slots.contains($0) }[...]
        for i in 0..<tileCount.rawValue where slots[i] == nil {
            guard let next = unused.popFirst() else { break }
            slots[i] = next
        }
    }

    /// Starts tiles for visible positions whose channel changed, and stops
    /// tiles that are hidden or empty.
    private func syncTiles(channels: [Channel]? = nil) {
        let channels = channels ?? library.channels
        for i in 0..<Self.positionCount {
            let wanted = i < tileCount.rawValue ? slots[i] : nil
            if tiles[i]?.channel.id == wanted { continue }
            tiles[i]?.stop()
            tiles[i] = nil
            if let wanted, let channel = channels.first(where: { $0.id == wanted }) {
                tiles[i] = TileModel(channel: channel)
            }
        }
        applyMute()
        applyVisibility()
    }

    /// Pauses tiles hidden behind a zoomed-in tile and resumes the rest.
    private func applyVisibility() {
        let visible = layout.visibleCells
        for (i, tile) in tiles {
            tile.setActive(visible[i] != nil)
        }
    }

    private func applyMute() {
        for (i, tile) in tiles {
            tile.isMuted = (i != focused)
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(tileCount.rawValue, forKey: Keys.tileCount)
        defaults.set(slots.map { $0 ?? "" }, forKey: Keys.slots)
    }
}
