import AppKit
import Combine
import Foundation

/// Every channel you might want on screen, in the order the pickers show them.
///
/// Saved as `~/Library/Application Support/Watch/channels.json`. The file can
/// be edited by hand (entries can be plain strings; see `Channel`'s Codable);
/// Watch reloads it whenever the app comes back to the front.
@MainActor
final class ChannelLibrary: ObservableObject {
    @Published private(set) var channels: [Channel] = []

    let fileURL: URL
    private var loadedModificationDate: Date?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent("Watch", isDirectory: true)
            .appendingPathComponent("channels.json")

        if !load() {
            channels = Self.seed()
            if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadIfChangedOnDisk() }
            .store(in: &cancellables)
    }

    func channel(id: String) -> Channel? {
        channels.first { $0.id == id }
    }

    // MARK: - Editing

    /// Adds a channel at the end. Returns false if it's already in the list.
    @discardableResult
    func add(_ channel: Channel) -> Bool {
        guard self.channel(id: channel.id) == nil else { return false }
        channels.append(channel)
        save()
        return true
    }

    func remove(ids: Set<String>) {
        channels.removeAll { ids.contains($0.id) }
        save()
    }

    func rename(id: String, to name: String) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? nil : trimmed
        guard channels[index].name != newName else { return }
        channels[index].name = newName
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        channels.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - File

    /// Reads channels.json. Returns false if it's missing or unreadable;
    /// entries it can't make sense of are skipped.
    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        do {
            let entries = try JSONDecoder().decode([LenientEntry].self, from: data)
            var seen = Set<String>()
            channels = entries.compactMap(\.channel).filter { seen.insert($0.id).inserted }
            loadedModificationDate = modificationDate()
            return true
        } catch {
            FileHandle.standardError.write(Data("Watch: couldn't read \(fileURL.path): \(error)\n".utf8))
            return false
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(channels).write(to: fileURL, options: .atomic)
            loadedModificationDate = modificationDate()
        } catch {
            FileHandle.standardError.write(Data("Watch: couldn't save \(fileURL.path): \(error)\n".utf8))
        }
    }

    private func reloadIfChangedOnDisk() {
        guard let date = modificationDate(), date != loadedModificationDate else { return }
        load()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// First launch: the channels from before there was a list (the last set
    /// passed on the command line), then the defaults.
    private static func seed() -> [Channel] {
        let previous = (UserDefaults.standard.stringArray(forKey: "channels") ?? [])
            .compactMap { Channel(input: $0) }
        var seen = Set<String>()
        return (previous + Channel.defaults).filter { seen.insert($0.id).inserted }
    }

    private struct LenientEntry: Decodable {
        let channel: Channel?
        init(from decoder: Decoder) throws {
            channel = try? Channel(from: decoder)
        }
    }
}
