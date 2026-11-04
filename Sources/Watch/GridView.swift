import AVKit
import SwiftUI

struct GridView: View {
    @ObservedObject var model: GridModel
    @ObservedObject var library: ChannelLibrary
    @Environment(\.openSettings) private var openSettings

    private let spacing: CGFloat = 2
    private static let gridSpace = "grid"

    /// The tile being dragged to another spot. Resets on its own if the drag
    /// is cancelled (say, the grid zooms mid-drag).
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.25)))
    private var drag: Drag?

    private struct Drag: Equatable {
        var position: Int
        var translation: CGSize
        /// The other spot under the cursor, if any.
        var target: Int?
    }

    /// One spot in the grid. Its identity is the running tile, so a tile
    /// that's swapped to another spot keeps its view (and its picture) and
    /// slides there instead of being rebuilt.
    private struct Spot: Identifiable {
        enum ID: Hashable {
            case tile(ObjectIdentifier)
            case empty(Int)
        }
        let position: Int
        let id: ID
    }

    var body: some View {
        GeometryReader { geo in
            let count = model.tileCount.rawValue
            let columnCount = Self.bestColumns(for: count, in: geo.size, spacing: spacing)
            // Use the window's column count right away rather than waiting
            // for the model to catch up, so resizing never draws a stale grid.
            let layout = GridLayout(count: count, columns: columnCount, zoom: model.zoom)
            let visible = layout.visibleCells
            let spots = (0..<count).map { position in
                Spot(position: position,
                     id: model.tiles[position].map { .tile(ObjectIdentifier($0)) } ?? .empty(position))
            }

            ZStack(alignment: .topLeading) {
                ForEach(spots) { spot in
                    let position = spot.position
                    let frame = rect(for: layout.frameCell(position), in: layout, size: geo.size)
                    let isVisible = visible[position] != nil
                    let isDragged = drag?.position == position
                    let moved = isDragged ? drag?.translation ?? .zero : .zero

                    tile(at: position)
                        .frame(width: frame.width, height: frame.height)
                        .overlay {
                            if drag?.target == position {
                                Rectangle().strokeBorder(.white.opacity(0.6), lineWidth: 4)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { handleDoubleClick(position) }
                        .onTapGesture { handleTap(position) }
                        // Drag a tile onto another to swap them; only in the
                        // plain grid, where every spot is showing.
                        .gesture(dragGesture(for: position, in: layout, size: geo.size),
                                 including: model.zoom == .grid ? .all : .subviews)
                        .contextMenu { channelMenu(for: position) }
                        .scaleEffect(isDragged ? 0.85 : 1)
                        .opacity(isDragged ? 0.85 : 1)
                        .shadow(color: .black.opacity(isDragged ? 0.6 : 0), radius: 16)
                        .animation(.snappy(duration: 0.15), value: isDragged)
                        .offset(x: frame.minX + moved.width, y: frame.minY + moved.height)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                        .zIndex(isDragged ? 2 : position == layout.zoom.target ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.gridSpace))
            .animation(.snappy(duration: 0.25), value: model.zoom)
            .onChange(of: columnCount, initial: true) { _, newValue in
                model.setColumns(newValue)
            }
        }
        .background(.black)
    }

    private func dragGesture(for position: Int, in layout: GridLayout, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.gridSpace))
            .updating($drag) { value, drag, _ in
                let target = self.position(at: value.location, in: layout, size: size)
                drag = Drag(position: position,
                            translation: value.translation,
                            target: target == position ? nil : target)
            }
            .onEnded { value in
                guard let target = self.position(at: value.location, in: layout, size: size) else { return }
                handleDrop(position, on: target)
            }
    }

    /// The size of one grid cell in points, not counting the gaps.
    private func cellSize(in layout: GridLayout, size: CGSize) -> CGSize {
        CGSize(width: (size.width - spacing * CGFloat(layout.columns - 1)) / CGFloat(layout.columns),
               height: (size.height - spacing * CGFloat(layout.rows - 1)) / CGFloat(layout.rows))
    }

    /// A cell's rectangle in points, including the gaps it spans.
    private func rect(for cell: GridLayout.Cell, in layout: GridLayout, size: CGSize) -> CGRect {
        let cellSize = cellSize(in: layout, size: size)
        return CGRect(
            x: CGFloat(cell.column) * (cellSize.width + spacing),
            y: CGFloat(cell.row) * (cellSize.height + spacing),
            width: CGFloat(cell.width) * cellSize.width + CGFloat(cell.width - 1) * spacing,
            height: CGFloat(cell.height) * cellSize.height + CGFloat(cell.height - 1) * spacing)
    }

    /// The grid position under a point, or nil if it's outside the grid or
    /// in the empty end of a short last row.
    private func position(at point: CGPoint, in layout: GridLayout, size: CGSize) -> Int? {
        guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return nil }
        let cellSize = cellSize(in: layout, size: size)
        let column = min(Int(point.x / (cellSize.width + spacing)), layout.columns - 1)
        let row = min(Int(point.y / (cellSize.height + spacing)), layout.rows - 1)
        let position = row * layout.columns + column
        return position < layout.count ? position : nil
    }

    @ViewBuilder
    private func tile(at position: Int) -> some View {
        let isFocused = model.focused == position
        if let tile = model.tiles[position] {
            TileView(
                tile: tile,
                title: library.channel(id: tile.channel.id)?.displayName ?? tile.channel.displayName,
                isFocused: isFocused)
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
        withAnimation(.snappy(duration: 0.25)) {
            model.assign(channel.id, to: position)
        }
    }

    private func handleDrop(_ position: Int, on target: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            model.swap(position, target)
        }
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
