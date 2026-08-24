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
            storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true }
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
            storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true }
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
            storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true }
        )

        await coordinator.start()

        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 0)
        XCTAssertNil(coordinator.currentItem)
        if case .failed = coordinator.phase { } else { XCTFail("Expected failed phase") }
    }

    func testInterruptionFinalizesCaptureAndPersistsFinalEvent() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        _ = try fixture.repository.addMarker(to: item, positionMilliseconds: 13_000)
        let interruptionDate = Date(timeIntervalSince1970: 100)

        recorder.send(.interruptionBegan(interruptionDate))
        try await waitUntil { recorder.finishCount == 1 && coordinator.phase == .available(item.id) }

        XCTAssertEqual(item.localState, .available)
        XCTAssertTrue(item.endedUnexpectedly)
        XCTAssertEqual(item.durationMilliseconds, 12_340)
        XCTAssertTrue(item.markers.isEmpty)
        XCTAssertEqual(item.events.map(\.kind), [.interruptionBegan])
        XCTAssertEqual(item.events.first?.startedAt, interruptionDate)
        coordinator.addMarker()
        XCTAssertTrue(item.markers.isEmpty)
    }

    func testInterruptionFinishFailureRecoversVerifiedFragment() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder(finishError: TestError.failed)
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        recorder.send(.interruptionBegan(.now))
        try await waitUntil { coordinator.phase == .available(item.id) }

        XCTAssertEqual(item.localState, .recovered)
        XCTAssertTrue(item.endedUnexpectedly)
        XCTAssertEqual(item.durationMilliseconds, 12_340)
    }

    func testStartingAfterInterruptionCreatesSeparateAudio() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let interruptedID = coordinator.currentItem?.id else { return XCTFail("Missing first Audio") }
        recorder.send(.interruptionBegan(.now))
        try await waitUntil { coordinator.phase == .available(interruptedID) }

        await coordinator.start()

        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertNotEqual(coordinator.currentItem?.id, interruptedID)
        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 2)
    }

    func testSecondCaptureAlsoFinalizesOnInterruption() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let firstID = coordinator.currentItem?.id else { return XCTFail("Missing first Audio") }
        recorder.send(.interruptionBegan(Date(timeIntervalSince1970: 100)))
        try await waitUntil { coordinator.phase == .available(firstID) }

        await coordinator.start()
        guard let secondItem = coordinator.currentItem else { return XCTFail("Missing second Audio") }
        recorder.send(.interruptionBegan(Date(timeIntervalSince1970: 200)))
        try await waitUntil { coordinator.phase == .available(secondItem.id) }

        XCTAssertEqual(recorder.finishCount, 2)
        XCTAssertEqual(secondItem.events.map(\.kind), [.interruptionBegan])
        XCTAssertTrue(secondItem.endedUnexpectedly)
    }

    func testRouteChangePersistsResultingInputNameAndCaptureContinues() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        let originalAudioID = coordinator.currentItem?.id
        recorder.send(.routeChanged(.now, inputName: "USB Microphone"))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.inputName, "USB Microphone")
        XCTAssertEqual(coordinator.currentItem?.events.first?.inputName, "USB Microphone")
        XCTAssertEqual(coordinator.currentItem?.events.first?.kind, .routeChanged)
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertEqual(coordinator.currentItem?.id, originalAudioID)
        XCTAssertEqual(recorder.finishCount, 0)
    }

    func testUnavailableInputFinalizesWithRouteEvent() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        recorder.send(.inputBecameUnavailable(Date(timeIntervalSince1970: 100)))
        try await waitUntil { coordinator.phase == .available(item.id) }

        XCTAssertEqual(coordinator.inputName, CaptureEvent.noInputName)
        XCTAssertTrue(item.endedUnexpectedly)
        XCTAssertEqual(item.events.map(\.kind), [.routeChanged])
        XCTAssertEqual(item.events.first?.inputName, CaptureEvent.noInputName)
        XCTAssertEqual(recorder.finishCount, 1)
    }

    func testInterruptionRemainsFinalEventWhenLaterRecorderEventsArrive() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder()
        let coordinator = CaptureCoordinator(repository: fixture.repository, recorder: recorder, inspector: FixedInspector(), storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true })

        await coordinator.start()
        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        recorder.send(.routeChanged(Date(timeIntervalSince1970: 99), inputName: "USB Microphone"))
        try await waitUntil { item.events.count == 1 }
        recorder.send(.interruptionBegan(Date(timeIntervalSince1970: 100)))
        recorder.send(.routeChanged(Date(timeIntervalSince1970: 101), inputName: "Built-in Microphone"))
        try await waitUntil { coordinator.phase == .available(item.id) }

        XCTAssertEqual(item.events.map(\.kind), [.routeChanged, .interruptionBegan])
        XCTAssertEqual(coordinator.inputName, "USB Microphone")
    }

    func testNonemptyStartFailurePreservesAudioAsNeedsRecovery() async throws {
        let fixture = try Fixture()
        let recorder = FakeRecorder(error: TestError.failed, writesBytesBeforeFailing: true)
        let coordinator = CaptureCoordinator(
            repository: fixture.repository,
            recorder: recorder,
            inspector: FixedInspector(),
            storageMonitor: AlwaysSufficientStorageMonitor(), permissionProvider: { true }
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

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw TestError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum TestError: Error { case failed, timedOut }

    private final class AlwaysSufficientStorageMonitor: StorageMonitoring {
        var assessment: StorageAssessment = .sufficient(estimatedDuration: .seconds(24 * 60 * 60))
        func refresh() -> StorageAssessment { assessment }
    }

    @MainActor
    private final class FakeRecorder: CaptureRecorder {
        let events: AsyncStream<CaptureRecorderEvent>
        private let eventContinuation: AsyncStream<CaptureRecorderEvent>.Continuation
        let error: Error?
        let finishError: Error?
        let writesBytesBeforeFailing: Bool
        private(set) var didStart = false
        private(set) var startCount = 0
        private(set) var finishCount = 0
        private var outputURL: URL?

        init(error: Error? = nil, finishError: Error? = nil, writesBytesBeforeFailing: Bool = false) {
            var continuation: AsyncStream<CaptureRecorderEvent>.Continuation?
            self.events = AsyncStream { continuation = $0 }
            self.eventContinuation = continuation!
            self.error = error
            self.finishError = finishError
            self.writesBytesBeforeFailing = writesBytesBeforeFailing
        }

        func start(outputURL: URL) async throws {
            didStart = true
            startCount += 1
            self.outputURL = outputURL
            if writesBytesBeforeFailing { try Data("partial".utf8).write(to: outputURL) }
            if let error { throw error }
        }

        func finish() async throws {
            finishCount += 1
            if let finishError { throw finishError }
        }

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
