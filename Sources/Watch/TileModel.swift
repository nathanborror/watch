import AVFoundation
import Combine
import Foundation

/// One tile: a channel, its player, and the loop that keeps it playing.
@MainActor
final class TileModel: ObservableObject, Identifiable {
    enum State: Equatable {
        case loading
        case playing
        case failed(String)
    }

    let id = UUID()
    let channel: Channel
    let player = AVPlayer()

    @Published private(set) var state: State = .loading

    private var observers: [NSKeyValueObservation] = []
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var isStopped = false

    /// False while the tile is hidden behind a zoomed-in tile. Hidden tiles
    /// stay loaded but paused.
    private(set) var isActive = true

    /// YouTube's manifests expire after ~6 h; re-resolve well before that.
    private let refreshInterval: TimeInterval = 4 * 60 * 60
    private let maxRetryDelay: TimeInterval = 10 * 60

    /// Starts at the site's base delay and doubles with each failure in a row,
    /// so a rate-limited or offline channel stops hammering the site.
    private var retryDelay: TimeInterval {
        let base = channel.site.retryDelay
        return min(base * pow(2, Double(max(consecutiveFailures - 1, 0))), maxRetryDelay)
    }

    init(channel: Channel) {
        self.channel = channel
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        load()
    }

    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    /// Pauses a hidden tile, or resumes one coming back into view. Resuming
    /// jumps to the live edge rather than picking up where it paused.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            resumeAtLiveEdge()
        } else {
            player.pause()
        }
    }

    private func resumeAtLiveEdge() {
        if let live = player.currentItem?.seekableTimeRanges.last?.timeRangeValue,
           live.duration.seconds > 0 {
            player.seek(to: live.end)
        }
        player.play()
    }

    /// Stops playback and the resolve/refresh loop for good. Call before
    /// dropping the tile.
    func stop() {
        isStopped = true
        refreshTask?.cancel()
        refreshTask = nil
        observers.removeAll()
        cancellables.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    func load() {
        guard !isStopped else { return }
        refreshTask?.cancel()
        state = .loading
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await StreamResolver.resolve(channel)
                guard !Task.isCancelled else { return }
                play(url)
                try await Task.sleep(for: .seconds(refreshInterval))
                load()
            } catch is CancellationError {
                // reload requested; nothing to do
            } catch {
                consecutiveFailures += 1
                state = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(retryDelay))
                guard !Task.isCancelled else { return }
                load()
            }
        }
    }

    private func play(_ url: URL) {
        observers.removeAll()
        cancellables.removeAll()

        let item = AVPlayerItem(url: url)
        // Keep latency down for live content.
        item.preferredForwardBufferDuration = 2

        observers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.state = .playing
                    self?.consecutiveFailures = 0
                case .failed: self?.failAndRetry(item.error?.localizedDescription ?? "Playback failed")
                default: break
                }
            }
        })

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.failAndRetry("Stream ended") }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, isActive else { return }
                player.play()
            }
            .store(in: &cancellables)

        player.replaceCurrentItem(with: item)
        if isActive { player.play() }
    }

    private func failAndRetry(_ message: String) {
        guard !isStopped else { return }
        consecutiveFailures += 1
        state = .failed(message)
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(retryDelay))
            guard !Task.isCancelled else { return }
            load()
        }
    }
}
