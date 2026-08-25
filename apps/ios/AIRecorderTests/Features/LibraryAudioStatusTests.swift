import XCTest
@testable import AIRecorder

final class LibraryAudioStatusTests: XCTestCase {
    func testVerifiedCloudBackupIsShownInTheLibrary() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .backedUp

        XCTAssertEqual(libraryAudioStatus(for: item), .backedUpInCloud)
    }

    func testFailedCloudBackupOutranksAvailableLocalAudio() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .failed

        XCTAssertEqual(libraryAudioStatus(for: item), .uploadFailed)
    }

    func testPausedCloudBackupOutranksAvailableLocalAudio() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .paused

        XCTAssertEqual(libraryAudioStatus(for: item), .uploadPaused)
    }

    func testCloudOnlyOutranksBackedUpStatus() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .backedUp
        item.localOriginalAudioRemovedAt = .now

        XCTAssertEqual(libraryAudioStatus(for: item), .cloudOnly)
    }

    func testBackedUpAudioOutranksOnlyOnThisIPhone() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .backedUp

        XCTAssertEqual(libraryAudioStatus(for: item), .backedUpInCloud)
    }

    func testStableLocationStatusesExposeOrderedSFSymbols() {
        XCTAssertEqual(LibraryAudioStatus.onlyOnThisIPhone.locationSymbolNames, ["iphone.gen3"])
        XCTAssertEqual(LibraryAudioStatus.cloudOnly.locationSymbolNames, ["icloud"])
        XCTAssertEqual(LibraryAudioStatus.backedUpInCloud.locationSymbolNames, ["iphone", "icloud"])
    }

    func testOperationalStatusesDoNotExposeLocationSymbols() {
        XCTAssertNil(LibraryAudioStatus.uploading.locationSymbolNames)
        XCTAssertNil(LibraryAudioStatus.uploadFailed.locationSymbolNames)
        XCTAssertNil(LibraryAudioStatus.needsRecovery.locationSymbolNames)
    }

    func testStatePresentationSeparatesLocalCloudAndProcessingStates() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .paused

        XCTAssertEqual(audioStatePresentation(for: item).localAudio, .available)
        XCTAssertEqual(audioStatePresentation(for: item).cloudAudio, .paused)
        XCTAssertEqual(audioStatePresentation(for: item).processing, .notStarted)
    }

    func testStatePresentationShowsCloudOnlyAfterVerifiedLocalDeletion() {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        item.cloudBackupState = .backedUp
        item.localOriginalAudioRemovedAt = .now

        XCTAssertEqual(audioStatePresentation(for: item).localAudio, .removed)
        XCTAssertEqual(audioStatePresentation(for: item).cloudAudio, .backedUp)
        XCTAssertEqual(libraryAudioStatus(for: item), .cloudOnly)
    }
}
