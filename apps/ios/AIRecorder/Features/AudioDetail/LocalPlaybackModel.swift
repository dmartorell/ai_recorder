import AVFoundation
import Observation

@MainActor
protocol LocalPlaybackPlayer: AnyObject {
    var isPlaying: Bool { get }
    var currentTimeSeconds: Double { get }
    func play()
    func pause()
    func seek(to seconds: Double)
    func isCurrentItem(_ item: Any) -> Bool
}

@MainActor
final class AVPlayerPlaybackPlayer: LocalPlaybackPlayer {
    private let player: AVPlayer

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    var isPlaying: Bool { player.rate > 0 }
    var currentTimeSeconds: Double { max(0, player.currentTime().seconds) }

    func play() {
        // Seeking first also wakes an AVPlayerItem that has not loaded its
        // local fragmented-M4A track yet.
        player.seek(
            to: CMTime(seconds: currentTimeSeconds, preferredTimescale: 1_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player.playImmediately(atRate: 1)
    }
    func pause() { player.pause() }
    func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 1_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
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
    private(set) var isPlaying = false
    private(set) var positionSeconds = 0.0

    init(player: any LocalPlaybackPlayer) {
        self.player = player
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

    func seek(to seconds: Double, autoplay: Bool = true) {
        positionSeconds = max(0, seconds)
        player.seek(to: positionSeconds)
        if autoplay {
            player.play()
            isPlaying = true
        }
    }

    func restartPlayback() {
        seek(to: 0)
    }

    func isCurrentItem(_ item: Any) -> Bool {
        player.isCurrentItem(item)
    }

    func handlePlaybackEnded() {
        player.pause()
        player.seek(to: 0)
        positionSeconds = 0
        isPlaying = false
    }
}
