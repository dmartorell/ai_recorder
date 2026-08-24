import XCTest

@MainActor
final class LocalRecordingFlowUITests: XCTestCase {
    func testLibraryOpensPreparationForANewAudio() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-app-language", "en"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Recording"].waitForExistence(timeout: 5))
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
        app.launchArguments = ["-ui-testing", "-app-language", "en"]
        app.launch()

        app.buttons["Record"].tap()
        XCTAssertTrue(app.navigationBars["Prepare"].waitForExistence(timeout: 5))
        app.buttons["Record now"].tap()

        XCTAssertTrue(app.navigationBars["Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add marker"].exists)
        app.buttons["Add marker"].tap()
        XCTAssertTrue(app.buttons["Add marker"].exists)
        app.buttons["Finalize"].tap()
        let confirmation = app.buttons.matching(identifier: "Finalize").element(boundBy: 1)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.navigationBars["Recording"].waitForExistence(timeout: 5))
    }

    func testMetadataAndTwoStepDeletionKeepAudioUntilFinalConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-local-audio-fixture", "-app-language", "en"]
        app.launch()

        let audioRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Recording -'")).firstMatch
        XCTAssertTrue(audioRow.waitForExistence(timeout: 5))
        audioRow.tap()
        XCTAssertTrue(app.navigationBars["Recording"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.alerts["Delete local Recording?"].waitForExistence(timeout: 5))
        app.alerts["Delete local Recording?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Local source"].exists)

        app.buttons["Delete"].tap()
        app.alerts["Delete local Recording?"].buttons["Delete"].tap()
        let finalAlert = app.alerts.matching(NSPredicate(format: "label CONTAINS[c] 'Local source'")).firstMatch
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 5))
        finalAlert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Local source"].exists)

        app.buttons["Delete"].tap()
        app.alerts["Delete local Recording?"].buttons["Delete"].tap()
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 5))
        finalAlert.buttons["Delete"].tap()

        XCTAssertTrue(app.navigationBars["Recording"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Local source"].exists)
    }

    func testLibrarySwipeDeletionRequiresBothConfirmations() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-local-audio-fixture", "-app-language", "en"]
        app.launch()

        let audioRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Recording -'")).firstMatch
        XCTAssertTrue(audioRow.waitForExistence(timeout: 5))
        audioRow.swipeLeft()

        let deleteButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Delete Recording -'")
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        XCTAssertTrue(app.alerts["Delete local Recording?"].waitForExistence(timeout: 5))

        app.alerts["Delete local Recording?"].buttons["Delete"].tap()
        let permanentDeletionAlert = app.alerts.matching(
            NSPredicate(format: "label CONTAINS[c] 'permanently'")
        ).firstMatch
        XCTAssertTrue(permanentDeletionAlert.waitForExistence(timeout: 5))
        permanentDeletionAlert.buttons["Delete permanently"].tap()

        XCTAssertFalse(audioRow.waitForExistence(timeout: 2))
    }

    func testDraggingDownAcrossSelectionControlsSelectsEachCrossedRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-local-audio-fixtures", "-app-language", "en"]
        app.launch()

        app.buttons["Select"].tap()
        let selectionControls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'library-selection-'")
        )
        XCTAssertEqual(selectionControls.count, 3)

        selectionControls.element(boundBy: 0).press(
            forDuration: 0.1,
            thenDragTo: selectionControls.element(boundBy: 1)
        )

        XCTAssertTrue(app.buttons["Delete 2 selected Recordings"].waitForExistence(timeout: 5))
    }

    func testBulkDeletionRequiresBothConfirmations() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-local-audio-fixtures", "-app-language", "en"]
        app.launch()

        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 5))
        app.buttons["Select"].tap()

        let selectionControls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'library-selection-'")
        )
        XCTAssertEqual(selectionControls.count, 3)
        selectionControls.element(boundBy: 0).tap()
        selectionControls.element(boundBy: 1).tap()

        let trash = app.buttons["Delete 2 selected Recordings"]
        XCTAssertTrue(trash.exists)
        trash.tap()
        XCTAssertTrue(app.alerts["Delete 2 local Recording items?"].waitForExistence(timeout: 5))
        app.alerts["Delete 2 local Recording items?"].buttons["Cancel"].tap()
        XCTAssertEqual(selectionControls.count, 3)

        trash.tap()
        app.alerts["Delete 2 local Recording items?"].buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete 2 Recording items permanently?"].waitForExistence(timeout: 5))
        app.alerts["Delete 2 Recording items permanently?"].buttons["Cancel"].tap()
        XCTAssertEqual(selectionControls.count, 3)

        trash.tap()
        app.alerts["Delete 2 local Recording items?"].buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete 2 Recording items permanently?"].waitForExistence(timeout: 5))
        app.alerts["Delete 2 Recording items permanently?"].buttons["Delete permanently"].tap()

        let remainingAudioRows = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Recording -'")
        )
        XCTAssertEqual(remainingAudioRows.count, 1)
    }

    func testSpanishCaptureFlowUsesLocalizedControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-app-language", "es"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
        app.buttons["Grabar"].tap()
        XCTAssertTrue(app.navigationBars["Preparar"].waitForExistence(timeout: 5))
        app.buttons["Grabar ahora"].tap()
        XCTAssertTrue(app.navigationBars["Captura"].waitForExistence(timeout: 5))
        app.buttons["Añadir marcador"].tap()
        XCTAssertTrue(app.buttons["Añadir marcador"].exists)
    }

    func testPreparationCanBeCancelledWithoutCreatingAnAudio() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-app-language", "en"]
        app.launch()

        app.buttons["Record"].tap()
        XCTAssertTrue(app.navigationBars["Prepare"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].exists)
    }
}
