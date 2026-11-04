import SwiftUI
import AppKit

@main
struct WatchApp: App {
    @StateObject private var library: ChannelLibrary
    @StateObject private var model: GridModel

    init() {
        let library = ChannelLibrary()
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: GridModel(library: library))

        // `swift run` launches us as a plain process; make it a proper app
        // with a Dock icon and keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Watch") {
            GridView(model: model, library: library)
                .frame(minWidth: 640, minHeight: 360)
                .background(.black)
                .focusedSceneValue(\.isGridWindow, true)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            StreamCommands(model: model)
        }

        Settings {
            ChannelsView(library: library)
        }
    }
}

/// The Stream menu. Its single-key shortcuts (1–9, M, R, Esc) are only enabled
/// while the grid window is in front, so they don't swallow typing in the
/// Channels window.
struct StreamCommands: Commands {
    @ObservedObject var model: GridModel
    @FocusedValue(\.isGridWindow) private var isGridWindow

    var body: some Commands {
        CommandMenu("Stream") {
            ForEach(GridModel.TileCount.allCases) { count in
                Toggle("\(count.rawValue) Tiles", isOn: Binding(
                    get: { model.tileCount == count },
                    set: { if $0 { model.setTileCount(count) } }))
                    .keyboardShortcut(KeyEquivalent(Character("\(count.rawValue)")), modifiers: .command)
            }
            Divider()
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(isGridWindow != true)
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(isGridWindow != true || model.zoom == .grid)
            Button("Show All Tiles") { model.showAll() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(isGridWindow != true || model.zoom == .grid)
            Divider()
            ForEach(0..<GridModel.positionCount, id: \.self) { i in
                Button("Listen to Tile \(i + 1)") { model.focus(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    .disabled(isGridWindow != true || i >= model.tileCount.rawValue)
            }
            Divider()
            Button("Mute All") { model.focus(nil) }
                .keyboardShortcut("m", modifiers: [])
                .disabled(isGridWindow != true)
            Button("Reload Streams") { model.reloadAll() }
                .keyboardShortcut("r", modifiers: [])
                .disabled(isGridWindow != true)
        }
    }
}

private struct GridWindowKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    /// True while the grid window is the key window.
    var isGridWindow: Bool? {
        get { self[GridWindowKey.self] }
        set { self[GridWindowKey.self] = newValue }
    }
}
