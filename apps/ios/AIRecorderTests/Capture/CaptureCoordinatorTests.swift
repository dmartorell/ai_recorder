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
        XCTAssertTrue(recorder.didStart)
        XCTAssertEqual(try fixture.repository.context.fetch(FetchDescriptor<AudioItem>()).count, 1)

        await coordinator.finalize()

        guard let item = coordinator.currentItem else { return XCTFail("Missing Audio") }
        XCTAssertEqual(coordinator.phase, .available(item.id))
        XCTAssertEqual(item.localState, .available)
        XCTAssertEqual(item.durationMilliseconds, 12_340)
        XCTAssertNotNil(item.endedAt)
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
            container = try ModelContainer(for: AudioItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            repository = AudioRepository(context: container.mainContext, files: files)
        }
    }

    private enum TestError: Error { case failed }

    @MainActor
    private final class FakeRecorder: CaptureRecorder {
        let error: Error?
        let writesBytesBeforeFailing: Bool
        private(set) var didStart = false
        private var outputURL: URL?

        init(error: Error? = nil, writesBytesBeforeFailing: Bool = false) {
            self.error = error
            self.writesBytesBeforeFailing = writesBytesBeforeFailing
        }

        func start(outputURL: URL) async throws {
            didStart = true
            self.outputURL = outputURL
            if writesBytesBeforeFailing { try Data("partial".utf8).write(to: outputURL) }
            if let error { throw error }
        }

        func finish() async throws { }
    }

    private struct FixedInspector: AudioInspector {
        func inspect(_ url: URL) async throws -> CapturedAudioSummary {
            CapturedAudioSummary(duration: 12.34, channelCount: 1)
        }
    }
}
