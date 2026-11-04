import AVKit
import SwiftUI

struct GridView: View {
    @ObservedObject var model: GridModel
    @ObservedObject var library: ChannelLibrary
    @Environment(\.openSettings) private var openSettings

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let count = model.tileCount.rawValue
            let columnCount = Self.bestColumns(for: count, in: geo.size, spacing: spacing)
            // Use the window's column count right away rather than waiting
            // for the model to catch up, so resizing never draws a stale grid.
            let layout = GridLayout(count: count, columns: columnCount, zoom: model.zoom)
            let visible = layout.visibleCells

            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { position in
                    let frame = rect(for: layout.frameCell(position), in: layout, size: geo.size)
                    let isVisible = visible[position] != nil

                    tile(at: position)
                        .frame(width: frame.width, height: frame.height)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { handleDoubleClick(position) }
                        .onTapGesture { handleTap(position) }
                        .contextMenu { channelMenu(for: position) }
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                        .zIndex(position == layout.zoom.target ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.snappy(duration: 0.25), value: model.zoom)
            .onChange(of: columnCount, initial: true) { _, newValue in
                model.setColumns(newValue)
            }
        }
        .background(.black)
    }

    /// A cell's rectangle in points, including the gaps it spans.
    private func rect(for cell: GridLayout.Cell, in layout: GridLayout, size: CGSize) -> CGRect {
        let cellWidth = (size.width - spacing * CGFloat(layout.columns - 1)) / CGFloat(layout.columns)
        let cellHeight = (size.height - spacing * CGFloat(layout.rows - 1)) / CGFloat(layout.rows)
        return CGRect(
            x: CGFloat(cell.column) * (cellWidth + spacing),
            y: CGFloat(cell.row) * (cellHeight + spacing),
            width: CGFloat(cell.width) * cellWidth + CGFloat(cell.width - 1) * spacing,
            height: CGFloat(cell.height) * cellHeight + CGFloat(cell.height - 1) * spacing)
    }

    @ViewBuilder
    private func tile(at position: Int) -> some View {
        let isFocused = model.focused == position
        if let tile = model.tiles[position] {
            TileView(
                tile: tile,
                title: library.channel(id: tile.channel.id)?.displayName ?? tile.channel.displayName,
                isFocused: isFocused)
                .id(ObjectIdentifier(tile))
        } else {
            EmptyTileView(isFocused: isFocused)
        }
    }

    /// Right-click a tile to choose its channel. Picking one that's already on
    /// another tile swaps the two.
    @ViewBuilder
    private func channelMenu(for position: Int) -> some View {
        ForEach(library.channels) { channel in
            Toggle(channel.displayName, isOn: Binding(
                get: { model.slots[position] == channel.id },
                set: { _ in handlePick(channel, at: position) }))
        }
        if library.channels.isEmpty {
            Text("No channels yet")
        }
        Divider()
        Button("Edit Channels…") { handleEditChannels() }
    }

    private func handleTap(_ position: Int) {
        model.focus(model.focused == position ? nil : position)
    }

    /// Zooms in a step on the tile; on a full-window tile, back to the grid.
    private func handleDoubleClick(_ position: Int) {
        if model.zoom == .full(position) {
            model.showAll()
        } else {
            model.zoomIn(on: position)
        }
    }

    private func handlePick(_ channel: Channel, at position: Int) {
        model.assign(channel.id, to: position)
    }

    private func handleEditChannels() {
        openSettings()
    }

    /// The column count that shows the biggest 16:9 picture in each tile at
    /// this window size. Six tiles go 2×3 in a 16:10 window and 3×2 in a
    /// very wide one; resizing the window re-picks.
    static func bestColumns(for count: Int, in size: CGSize, spacing: CGFloat) -> Int {
        guard count > 1, size.width > 0, size.height > 0 else { return 1 }
        var best = 1
        var bestWidth: CGFloat = 0
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let cellWidth = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            // Width of the largest 16:9 picture that fits in the cell.
            let pictureWidth = min(cellWidth, cellHeight * 16 / 9)
            if pictureWidth > bestWidth + 0.5 {
                best = columns
                bestWidth = pictureWidth
            }
        }
        return best
    }
}

struct TileView: View {
    @ObservedObject var tile: TileModel
    let title: String
    let isFocused: Bool

    var body: some View {
        ZStack {
            PlayerLayerView(player: tile.player)

            switch tile.state {
            case .loading:
                ProgressView().controlSize(.large)
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Text("Retrying…").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .foregroundStyle(.white)
            case .playing:
                EmptyView()
            }

            VStack {
                HStack {
                    Label(title,
                          systemImage: isFocused ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .clipped()
        .overlay {
            if isFocused {
                Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
            }
        }
        .background(.black)
    }
}

/// A position with no channel: the list ran out, or its channel was removed.
struct EmptyTileView: View {
    let isFocused: Bool

    var body: some View {
        Text("Right-click to choose a channel")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .overlay {
                if isFocused {
                    Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
            }
    }
}

/// A bare AVPlayerLayer — no controls, no gestures, just video.
/// (AVKit's VideoPlayer adds a control bar that fights the tap-to-focus gesture.)
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Fill the tile edge to edge, cropping whatever overhangs, instead of letterboxing.
        playerLayer.videoGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
