import XCTest
@testable import AIRecorder

@MainActor
final class LocalPlaybackModelTests: XCTestCase {
    func testRestartFromNormalPlaybackSeeksToBeginningAndPlays() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.togglePlayback()
        model.restartPlayback()

        XCTAssertEqual(player.seekedSeconds, 0)
        XCTAssertEqual(player.playCount, 2)
        XCTAssertTrue(model.isPlaying)
    }

    func testSeekingAndSkippingClampToAudioDuration() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.seek(to: 55)
        model.skip(by: 10)
        XCTAssertEqual(model.positionSeconds, 60)

        model.skip(by: -70)
        XCTAssertEqual(model.positionSeconds, 0)
        XCTAssertEqual(player.seekedSeconds, 0)
    }

    func testPeriodicUpdatesAdvancePlaybackAndTeardownManageTimeObserver() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.togglePlayback()
        player.emitPeriodicTime(15.5)
        player.emitPeriodicTime(15.6)

        XCTAssertEqual(model.positionSeconds, 15.6)
        XCTAssertEqual(player.timeObserverInterval, 0.1)
        XCTAssertEqual(player.activeTimeObserverCount, 1)

        model.tearDown()
        XCTAssertEqual(player.activeTimeObserverCount, 0)
        XCTAssertEqual(player.pauseCount, 1)
    }

    func testPendingSeekIgnoresStalePeriodicPlayerUpdates() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.seek(to: 40)
        player.emitPeriodicTime(12)

        XCTAssertEqual(model.positionSeconds, 40)

        player.completeSeek()
        player.emitPeriodicTime(40.25)
        XCTAssertEqual(model.positionSeconds, 40.25)
    }

    func testScrubbingDefersPlayerSeekUntilTheGestureEnds() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.beginScrubbing()
        model.previewPosition(at: 20)
        model.previewPosition(at: 30)
        player.emitPeriodicTime(5)

        XCTAssertEqual(model.positionSeconds, 30)
        XCTAssertNil(player.seekedSeconds)

        model.endScrubbing()
        XCTAssertEqual(player.seekedSeconds, 30)
    }

    func testEndOfFileResetsPlayback() {
        let player = FakePlayer()
        let model = LocalPlaybackModel(player: player, durationSeconds: 60)

        model.seek(to: 42)
        model.handlePlaybackEnded()

        XCTAssertEqual(model.positionSeconds, 0)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(player.seekedSeconds, 0)
    }

    private final class FakePlayer: LocalPlaybackPlayer {
        private(set) var seekedSeconds: Double?
        private(set) var playCount = 0
        private(set) var pauseCount = 0
        private(set) var timeObserverInterval: Double?
        private var timeObservers: [UUID: @MainActor (Double) -> Void] = [:]

        var activeTimeObserverCount: Int { timeObservers.count }

        func play() { playCount += 1 }
        func pause() { pauseCount += 1 }
        private var seekCompletion: (@MainActor () -> Void)?

        func seek(to seconds: Double, completion: @escaping @MainActor () -> Void) {
            seekedSeconds = seconds
            seekCompletion = completion
        }

        func addPeriodicTimeObserver(
            interval: Double,
            handler: @escaping @MainActor (Double) -> Void
        ) -> Any {
            timeObserverInterval = interval
            let id = UUID()
            timeObservers[id] = handler
            return id
        }

        func removeTimeObserver(_ observer: Any) {
            guard let id = observer as? UUID else { return }
            timeObservers[id] = nil
        }

        func isCurrentItem(_ item: Any) -> Bool { false }

        func emitPeriodicTime(_ seconds: Double) {
            timeObservers.values.forEach { $0(seconds) }
        }

        func completeSeek() {
            let completion = seekCompletion
            seekCompletion = nil
            completion?()
        }
    }
}
