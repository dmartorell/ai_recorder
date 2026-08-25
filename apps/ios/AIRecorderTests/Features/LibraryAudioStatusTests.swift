import XCTest
@testable import AIRecorder

final class LibraryAudioStatusTests: XCTestCase {
    func testVerifiedCloudBackupIsShownInTheLibrary() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .backedUp

        XCTAssertEqual(libraryAudioStatus(for: item), .backedUpInCloud)
    }
}
