import XCTest

@MainActor
final class LocalRecordingFlowUITests: XCTestCase {
    func testLibraryOpensPreparationForANewAudio() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        let recordButton = app.buttons["Record"]
        XCTAssertTrue(recordButton.exists)
        recordButton.tap()

        XCTAssertTrue(app.navigationBars["Prepare"].waitForExistence(timeout: 5))
        let format = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'AAC-LC'"))
        XCTAssertTrue(format.firstMatch.exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testFakeCaptureFinalizesAndReturnsToLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["Record"].tap()
        XCTAssertTrue(app.navigationBars["Prepare"].waitForExistence(timeout: 5))
        app.buttons["Record now"].tap()

        XCTAssertTrue(app.navigationBars["Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add marker"].exists)
        app.buttons["Add marker"].tap()
        XCTAssertTrue(app.staticTexts["Marker added"].waitForExistence(timeout: 5))
        app.buttons["Finalize"].tap()
        let confirmation = app.buttons.matching(identifier: "Finalize").element(boundBy: 1)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
    }

    func testMetadataAndTwoStepDeletionKeepAudioUntilFinalConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-local-audio-fixture"]
        app.launch()

        let audioRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Audio -'")).firstMatch
        XCTAssertTrue(audioRow.waitForExistence(timeout: 5))
        audioRow.tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playback-back-10"].exists)
        XCTAssertTrue(app.buttons["playback-toggle"].exists)
        XCTAssertTrue(app.buttons["playback-forward-10"].exists)

        app.buttons["Edit metadata"].tap()
        XCTAssertTrue(app.navigationBars["Edit Metadata"].waitForExistence(timeout: 5))
        app.textFields["metadata-title"].tap()
        app.textFields["metadata-title"].typeText("Local source")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Local source"].waitForExistence(timeout: 5))

        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete local Audio?"].waitForExistence(timeout: 5))
        app.alerts["Delete local Audio?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Local source"].exists)

        app.buttons["Delete"].tap()
        app.alerts["Delete local Audio?"].buttons["Delete"].tap()
        let finalAlert = app.alerts.matching(NSPredicate(format: "label CONTAINS[c] 'Local source'")).firstMatch
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 5))
        finalAlert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Local source"].exists)

        app.buttons["Delete"].tap()
        app.alerts["Delete local Audio?"].buttons["Delete"].tap()
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 5))
        finalAlert.buttons["Delete"].tap()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Local source"].exists)
    }

    func testPreparationCanBeCancelledWithoutCreatingAnAudio() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["Record"].tap()
        XCTAssertTrue(app.navigationBars["Prepare"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].exists)
    }
}
