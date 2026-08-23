import Foundation
import SwiftData
import XCTest
@testable import AIRecorder

@MainActor
final class RecoveryServiceTests: XCTestCase {
    func testPlayableInterruptedAudioBecomesRecovered() async throws {
        let fixture = try Fixture()
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .capturing
        fixture.context.insert(item)
        try fixture.context.save()
        try fixture.files.prepare(for: item.id)
        try Data("partial audio".utf8).write(to: fixture.files.url(for: item.id))

        await RecoveryService(context: fixture.context, files: fixture.files, inspector: FixedInspector()).recoverInterruptedItems()

        XCTAssertEqual(item.localState, .recovered)
        XCTAssertTrue(item.endedUnexpectedly)
        XCTAssertEqual(item.durationMilliseconds, 7_500)
    }

    func testUnplayableNonemptyAudioBecomesNeedsRecovery() async throws {
        let fixture = try Fixture()
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .finalizing
        fixture.context.insert(item)
        try fixture.context.save()
        try fixture.files.prepare(for: item.id)
        try Data("not playable".utf8).write(to: fixture.files.url(for: item.id))

        await RecoveryService(context: fixture.context, files: fixture.files, inspector: FailingInspector()).recoverInterruptedItems()

        XCTAssertEqual(item.localState, .needsRecovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.files.url(for: item.id).path))
    }

    func testMissingOrEmptyAudioRemovesOnlyMetadata() async throws {
        let fixture = try Fixture()
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .capturing
        fixture.context.insert(item)
        try fixture.context.save()

        await RecoveryService(context: fixture.context, files: fixture.files, inspector: FixedInspector()).recoverInterruptedItems()

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AudioItem>()).count, 0)
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let files: AudioFileStore

        init() throws {
            container = try ModelContainer(for: AudioItem.self, Marker.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = container.mainContext
            files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
    }

    private struct FixedInspector: AudioInspector {
        func inspect(_ url: URL) async throws -> CapturedAudioSummary { CapturedAudioSummary(duration: 7.5, channelCount: 1) }
    }

    private struct FailingInspector: AudioInspector {
        func inspect(_ url: URL) async throws -> CapturedAudioSummary { throw TestError.invalidAudio }
    }

    private enum TestError: Error { case invalidAudio }
}
