import XCTest
@testable import AIRecorder

@MainActor
final class AudioSelectionModelTests: XCTestCase {
    func testToggleSelectsAndDeselectsAudio() {
        let id = UUID()
        let model = AudioSelectionModel()

        model.enter()
        model.toggle(id)
        XCTAssertEqual(model.selectedIDs, [id])

        model.toggle(id)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testSelectingInclusiveRangeAddsEveryAudioBetweenEndpoints() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let model = AudioSelectionModel()

        model.beginSelection(at: ids[1], orderedIDs: ids)
        model.extendSelection(to: ids[3], orderedIDs: ids)

        XCTAssertEqual(model.selectedIDs, Set(ids[1...3]))
    }

    func testRangeExtensionCanMoveUpThenDown() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let model = AudioSelectionModel()

        model.beginSelection(at: ids[2], orderedIDs: ids)
        model.extendSelection(to: ids[0], orderedIDs: ids)
        XCTAssertEqual(model.selectedIDs, Set(ids[0...2]))

        model.extendSelection(to: ids[3], orderedIDs: ids)
        XCTAssertEqual(model.selectedIDs, Set(ids))
    }

    func testRetainExistingIDsRemovesDeletedAudioFromSelection() {
        let ids = [UUID(), UUID(), UUID()]
        let model = AudioSelectionModel()

        model.enter()
        model.toggle(ids[0])
        model.toggle(ids[1])
        model.retainExistingIDs([ids[1], ids[2]])

        XCTAssertEqual(model.selectedIDs, [ids[1]])
    }

    func testCancelClearsSelectionAndExitsSelectionMode() {
        let id = UUID()
        let model = AudioSelectionModel()

        model.enter()
        model.toggle(id)
        model.cancel()

        XCTAssertFalse(model.isSelecting)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }
}
