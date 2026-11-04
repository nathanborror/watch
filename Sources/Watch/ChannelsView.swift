import AppKit
import SwiftUI

/// The Channels window (Watch ▸ Settings…, ⌘,): add, name, reorder, and
/// remove the channels the tile pickers offer.
struct ChannelsView: View {
    @ObservedObject var library: ChannelLibrary

    @State private var selection = Set<String>()
    @State private var newChannel = ""
    @State private var newName = ""
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(library.channels) { channel in
                    ChannelRow(channel: channel) { name in
                        library.rename(id: channel.id, to: name)
                    }
                    .tag(channel.id)
                }
                .onMove { source, destination in
                    library.move(fromOffsets: source, toOffset: destination)
                }
            }
            .onDeleteCommand { handleRemoveSelected() }

            Divider()

            HStack(spacing: 8) {
                Button {
                    handleRemoveSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove the selected channels")
                .disabled(selection.isEmpty)

                TextField("@handle, UC… ID, rumble:name, kick:name, or channel URL", text: $newChannel)
                    .onSubmit { handleAdd() }
                TextField("Name (optional)", text: $newName)
                    .frame(width: 150)
                    .onSubmit { handleAdd() }
                Button("Add") { handleAdd() }
                    .disabled(newChannel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)

            HStack {
                if let addError {
                    Text(addError).foregroundStyle(.red)
                } else {
                    Text("Drag to reorder. Double-click a name to rename.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show File in Finder") { handleShowInFinder() }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .padding([.horizontal, .bottom], 10)
        }
        .frame(minWidth: 560, minHeight: 380)
    }

    private func handleAdd() {
        guard let channel = Channel(input: newChannel, name: newName) else {
            addError = "That doesn't look like a YouTube, Rumble, or Kick channel."
            return
        }
        guard library.add(channel) else {
            addError = "\(channel.idLabel) is already in the list."
            return
        }
        newChannel = ""
        newName = ""
        addError = nil
    }

    private func handleRemoveSelected() {
        library.remove(ids: selection)
        selection.removeAll()
    }

    private func handleShowInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL])
    }
}

/// One channel: an editable friendly name, and the id it points at.
private struct ChannelRow: View {
    let channel: Channel
    let onRename: (String) -> Void

    @State private var name = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack {
            TextField(channel.idLabel, text: $name)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit { handleCommitName() }
                .onChange(of: isEditing) { _, editing in
                    if !editing { handleCommitName() }
                }
            Spacer()
            Text(channel.idLabel)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .onAppear { name = channel.name ?? "" }
        .onChange(of: channel.name) { _, newValue in
            if !isEditing { name = newValue ?? "" }
        }
    }

    private func handleCommitName() {
        onRename(name)
    }
}
