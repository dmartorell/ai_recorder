import AVFoundation
import Observation

@MainActor
protocol LocalPlaybackPlayer: AnyObject {
    func play()
    func pause()
    func seek(to seconds: Double, completion: @escaping @MainActor () -> Void)
    func addPeriodicTimeObserver(
        interval: Double,
        handler: @escaping @MainActor (Double) -> Void
    ) -> Any
    func removeTimeObserver(_ observer: Any)
    func isCurrentItem(_ item: Any) -> Bool
}

@MainActor
final class AVPlayerPlaybackPlayer: LocalPlaybackPlayer {
    private let player: AVPlayer

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double, completion: @escaping @MainActor () -> Void) {
        player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 1_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in completion() }
        }
    }

    func addPeriodicTimeObserver(
        interval: Double,
        handler: @escaping @MainActor (Double) -> Void
    ) -> Any {
        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 1_000),
            queue: .main
        ) { time in
            Task { @MainActor in
                handler(time.seconds.isFinite ? time.seconds : 0)
            }
        }
    }

    func removeTimeObserver(_ observer: Any) {
        player.removeTimeObserver(observer)
    }

    func isCurrentItem(_ item: Any) -> Bool {
        guard let item = item as? AVPlayerItem else { return false }
        return item === player.currentItem
    }
}

@MainActor
@Observable
final class LocalPlaybackModel {
    private let player: any LocalPlaybackPlayer
    private let durationSeconds: Double
    private var timeObserver: Any?
    private var pendingSeekPosition: Double?
    private(set) var isScrubbing = false

    private(set) var isPlaying = false
    private(set) var positionSeconds = 0.0

    init(player: any LocalPlaybackPlayer, durationSeconds: Double = .greatestFiniteMagnitude) {
        self.player = player
        self.durationSeconds = max(0, durationSeconds)
        timeObserver = player.addPeriodicTimeObserver(interval: 0.1) { [weak self] seconds in
            self?.updatePosition(seconds)
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func skip(by seconds: Double) {
        seek(to: positionSeconds + seconds)
    }

    func seek(to seconds: Double, autoplay: Bool = true) {
        requestSeek(to: clamped(seconds), autoplay: autoplay)
    }

    func beginScrubbing() {
        isScrubbing = true
    }

    func previewPosition(at seconds: Double) {
        positionSeconds = clamped(seconds)
    }

    func endScrubbing() {
        isScrubbing = false
        requestSeek(to: positionSeconds, autoplay: isPlaying)
    }

    func restartPlayback() {
        seek(to: 0)
    }

    func isCurrentItem(_ item: Any) -> Bool {
        player.isCurrentItem(item)
    }

    func handlePlaybackEnded() {
        player.pause()
        pendingSeekPosition = nil
        player.seek(to: 0) { }
        positionSeconds = 0
        isPlaying = false
    }

    func tearDown() {
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
        player.pause()
        isPlaying = false
    }

    private func requestSeek(to seconds: Double, autoplay: Bool) {
        positionSeconds = seconds
        pendingSeekPosition = seconds
        player.seek(to: seconds) { [weak self] in
            guard let self, self.pendingSeekPosition == seconds else { return }
            self.pendingSeekPosition = nil
        }
        if autoplay {
            player.play()
            isPlaying = true
        }
    }

    private func updatePosition(_ seconds: Double) {
        guard !isScrubbing, pendingSeekPosition == nil else { return }
        positionSeconds = clamped(seconds)
    }

    private func clamped(_ seconds: Double) -> Double {
        min(durationSeconds, max(0, seconds))
    }
}
