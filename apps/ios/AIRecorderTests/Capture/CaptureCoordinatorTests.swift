import Foundation
import SwiftData
import XCTest
@testable import AIRecorder

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    func testStartCreatesAudioBeforeRecorderAndFinalizePersistsResult() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(
            repository: fixture.repository,
            recorder: recorder,
            inspector: FixedInspector(),
            permissionProvider: { true }
        )

        await coordinator.start()

        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertNotNil(coordinator.currentItem)
        coordinator.addMarker()
        XCTAssertEqual(coordinator.currentItem?.markers.count, 1)
        XCTAssertEqual(coordinator.markerCount, 1)
        XCTAssertTrue(recorder.didStart)
        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 1)

        await coordinator.finalize()

        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        XCTAssertEqual(coordinator.phase, .available(item.id))
        XCTAssertEqual(item.localState, .available)
        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).first?.localState, .available)
        XCTAssertEqual(item.durationMilliseconds, 12_340)
        XCTAssertNotNil(item.endedAt)
    }

    func testCanStartAnotherCaptureAfterFinalizing() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(
            repository: fixture.repository,
            recorder: recorder,
            inspector: FixedInspector(),
            permissionProvider: { true }
        )

        await coordinator.start()
        await coordinator.finalize()
        await coordinator.start()

        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 2)
        XCTAssertEqual(recorder.startCount, 2)
    }

    func testEmptyStartFailureRemovesOnlyEmptyAudio() async throws {
        let fixture = try Fixture()
        let coordinator = CaptureCoordinator(
            repository: fixture.repository,
            recorder: FakeRecorder(error: TestError.failed),
            inspector: FixedInspector(),
            permissionProvider: { true }
        )

        await coordinator.start()

        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 0)
        XCTAssertNil(coordinator.currentItem)
        if case .failed = coordinator.phase { } else { XCTFail("Expected failed phase") }
    }

    func testInterruptionPausesTimelineAndBlocksMarkersUntilSafeResume() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), permissionProvider: { true })

        await coordinator.start()
        try await Task.sleep(for: .milliseconds(150))
        let beforeInterruption = coordinator.currentAudioPositionMilliseconds
        let interruptionDate = Date(timeIntervalSince1970: 100)
        recorder.send(.interruptionBegan(interruptionDate))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.phase, .interrupted(startedAt: interruptionDate))
        XCTAssertLessThanOrEqual(abs(coordinator.currentAudioPositionMilliseconds - beforeInterruption), 100)
        coordinator.addMarker()
        XCTAssertEqual(coordinator.markerCount, 0)

        recorder.send(.interruptionEnded(.init(timeIntervalSince1970: 101), shouldResume: true))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertEqual(Set(coordinator.currentItem?.events.map(\.kind) ?? []), [.interruptionBegan, .interruptionEnded])
    }

    func testRouteChangePersistsResultingInputName() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), permissionProvider: { true })

        await coordinator.start()
        recorder.send(.routeChanged(.now, inputName: "USB Microphone"))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.inputName, "USB Microphone")
        XCTAssertEqual(coordinator.currentItem?.events.first?.inputName, "USB Microphone")
        XCTAssertEqual(coordinator.currentItem?.events.first?.kind, .routeChanged)
    }

    func testNonemptyStartFailurePreservesAudioAsNeedsRecovery() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder(error: TestError.failed, writesBytesBeforeFailing: true)
        let coordinator = CaptureCoordinator(
            repository: fixture.repository,
            recorder: recorder,
            inspector: FixedInspector(),
            permissionProvider: { true }
        )

        await coordinator.start()

        guard let item = coordinator.currentItem else { return XCTFail("Missing preserved Audio") }
        XCTAssertEqual(item.localState, .needsRecovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.files.url(for: item.id).path))
        if case .needsRecovery(item.id, _) = coordinator.phase { } else { XCTFail("Expected recovery phase") }
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let repository: AudioRepository
        let files: AudioFileStore

        init() throws {
            container = try ModelContainer(for: AudioItem.self, Marker.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            repository = AudioRepository(context: container.mainContext, files: files)
        }
    }

    private enum TestError: Error { case failed }

    @MainActor
    private final class FakeRecorder: CaptureRecorder {
        let events: AsyncStream<CaptureRecorderEvent>
        private let eventContinuation: AsyncStream<CaptureRecorderEvent>.Continuation
        let error: Error?
        let writesBytesBeforeFailing: Bool
        private(set) var didStart = false
        private(set) var startCount = 0
        private var outputURL: URL?

        init(error: Error? = nil, writesBytesBeforeFailing: Bool = false) {
            var continuation: AsyncStream<CaptureRecorderEvent>.Continuation?
            self.events = AsyncStream { continuation = $0 }
            self.eventContinuation = continuation!
            self.error = error
            self.writesBytesBeforeFailing = writesBytesBeforeFailing
        }

        func start(outputURL: URL) async throws {
            didStart = true
            startCount += 1
            self.outputURL = outputURL
            if writesBytesBeforeFailing { try Data("partial".utf8).write(to: outputURL) }
            if let error { throw error }
        }

        func finish() async throws { }

        func send(_ event: CaptureRecorderEvent) {
            eventContinuation.yield(event)
        }
    }

    private struct FixedInspector: AudioInspector {
        func inspect(_ url: URL) async throws -> CapturedAudioSummary {
            CapturedAudioSummary(duration: 12.34, channelCount: 1)
        }
    }
}
