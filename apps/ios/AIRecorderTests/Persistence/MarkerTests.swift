import SwiftData
import XCTest
@testable import AIRecorder

@MainActor
final class MarkerTests: XCTestCase {
    func testMarkerIsPersistedWithAudioAndKeepsStableIdentity() throws {
        let container = try ModelContainer(
            for: AudioItem.self, Marker.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let repository = AudioRepository(context: container.mainContext, files: files)
        let item = try repository.beginCapture()

        let first = try repository.addMarker(to: item, positionMilliseconds: 1_250)
        let second = try repository.addMarker(to: item, positionMilliseconds: 3_500)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(item.markers.map(\.positionMilliseconds).sorted(), [1_250, 3_500])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Marker>()).count, 2)
    }

    func testMarkersAreRejectedAfterCaptureFinalizes() throws {
        let container = try ModelContainer(
            for: AudioItem.self, Marker.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let repository = AudioRepository(context: container.mainContext, files: files)
        let item = try repository.beginCapture()
        item.localState = .available

        XCTAssertThrowsError(try repository.addMarker(to: item, positionMilliseconds: 100))
    }
}
