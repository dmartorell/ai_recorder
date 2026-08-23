import XCTest
@testable import AIRecorder

@MainActor
final class LocalPlaybackModelTests: XCTestCase {
    func testRestartFromNormalPlaybackSeeksToBeginningAndPlays() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player)

        model.togglePlayback()
        model.restartPlayback()

        XCTAssertEqual(player.seekedSeconds, 0)
        XCTAssertEqual(player.playCount, 2)
        XCTAssertTrue(model.isPlaying)
    }

    func testToggleUsesPlayerStateToResumeAfterAnExternalPause() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player)

        model.togglePlayback()
        player.pause()
        model.togglePlayback()

        XCTAssertEqual(player.playCount, 2)
        XCTAssertTrue(model.isPlaying)
    }

    func testRestartAfterSelectingMarkerReturnsToBeginningAndPlays() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player)

        model.seek(to: 42.5)
        model.restartPlayback()

        XCTAssertEqual(player.seekedSeconds, 0)
        XCTAssertEqual(model.positionSeconds, 0)
        XCTAssertTrue(model.isPlaying)
    }

    func testRestartFromPauseStartsPlaybackAtBeginning() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player)

        model.togglePlayback()
        model.togglePlayback()
        model.restartPlayback()

        XCTAssertEqual(player.seekedSeconds, 0)
        XCTAssertEqual(player.pauseCount, 1)
        XCTAssertTrue(model.isPlaying)
    }

    private final class FakePlayer: LocalPlaybackPlayer {
        private(set) var isPlaying = false
        private(set) var seekedSeconds: Double?
        private(set) var playCount = 0
        private(set) var pauseCount = 0

        func play() {
            playCount += 1
            isPlaying = true
        }

        func pause() {
            pauseCount += 1
            isPlaying = false
        }

        func seek(to seconds: Double) {
            seekedSeconds = seconds
        }

        func isCurrentItem(_ item: Any) -> Bool { false }
    }
}
