import Foundation
import XCTest
@testable import AIRecorder

final class BackupEligibilityTests: XCTestCase {
    func testAvailableNonemptyOriginalAudioIsEligible() throws {
        let fixture = Fixture()
        let item = fixture.item(state: .available)
        try Data("audio".utf8).write(to: fixture.files.url(for: item.id))

        XCTAssertEqual(BackupEligibility.forBackup(of: item, files: fixture.files), .eligible)
    }

    func testRecoveredNonemptyOriginalAudioIsEligible() throws {
        let fixture = Fixture()
        let item = fixture.item(state: .recovered)
        try Data("audio".utf8).write(to: fixture.files.url(for: item.id))

        XCTAssertEqual(BackupEligibility.forBackup(of: item, files: fixture.files), .eligible)
    }

    func testCapturingEmptyMissingAndNeedsRecoveryAudioAreIneligible() throws {
        let fixture = Fixture()

        XCTAssertEqual(BackupEligibility.forBackup(of: fixture.item(state: .capturing), files: fixture.files), .captureIsActive)
        XCTAssertEqual(BackupEligibility.forBackup(of: fixture.item(state: .needsRecovery), files: fixture.files), .originalAudioIsUnverified)

        let missing = fixture.item(state: .available)
        XCTAssertEqual(BackupEligibility.forBackup(of: missing, files: fixture.files), .originalAudioIsMissing)

        let empty = fixture.item(state: .available)
        try Data().write(to: fixture.files.url(for: empty.id))
        XCTAssertEqual(BackupEligibility.forBackup(of: empty, files: fixture.files), .originalAudioIsEmpty)
    }

    private struct Fixture {
        let files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        func item(state: LocalAudioState) -> AudioItem {
            try! FileManager.default.createDirectory(at: files.rootDirectory, withIntermediateDirectories: true)
            let item = AudioItem(fileName: "source.m4a")
            item.localState = state
            return item
        }
    }
}
