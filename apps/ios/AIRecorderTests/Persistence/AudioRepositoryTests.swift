import SwiftData
import XCTest
@testable import AIRecorder

@MainActor
final class AudioRepositoryTests: XCTestCase {
    func testBeginCapturePersistsItemBeforeReturningURL() throws {
        let fixture = try Fixture()
        let item = try fixture.repository.beginCapture()

        XCTAssertNotNil(try fixture.context.fetch(FetchDescriptor<AudioItem>()).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.files.rootDirectory.path))
        XCTAssertEqual(item.localState, .capturing)
    }

    func testStateTransitionsPersist() throws {
        let fixture = try Fixture()
        let item = try fixture.repository.beginCapture()

        try fixture.repository.markFinalizing(item)
        XCTAssertEqual(item.localState, .finalizing)
        try fixture.repository.markAvailable(item, durationMilliseconds: 1_250)
        XCTAssertEqual(item.localState, .available)
    }

    func testRecoveryTransitionMarksUnexpectedEnding() throws {
        let fixture = try Fixture()
        let item = try fixture.repository.beginCapture()
        try fixture.repository.markRecovered(item, durationMilliseconds: 800)

        XCTAssertEqual(item.localState, .recovered)
        XCTAssertTrue(item.endedUnexpectedly)
        XCTAssertEqual(item.durationMilliseconds, 800)
    }

    func testInvalidTransitionDoesNotMutateItem() throws {
        let fixture = try Fixture()
        let item = try fixture.repository.beginCapture()
        try fixture.repository.markFinalizing(item)

        XCTAssertThrowsError(try fixture.repository.markFinalizing(item))
        XCTAssertEqual(item.localState, .finalizing)
    }

    func testMetadataEditsDoNotChangeFileName() throws {
        let fixture = try Fixture()
        let item = try fixture.repository.beginCapture()
        let fileName = item.fileName

        item.customTitle = "Interview"
        item.context = "Field notes"
        try fixture.repository.save()

        XCTAssertEqual(item.fileName, fileName)
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let files: AudioFileStore
        let repository: AudioRepository

        init() throws {
            container = try ModelContainer(
                for: AudioItem.self, Marker.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
            files = AudioFileStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
            )
            repository = AudioRepository(context: context, files: files)
        }
    }
}
