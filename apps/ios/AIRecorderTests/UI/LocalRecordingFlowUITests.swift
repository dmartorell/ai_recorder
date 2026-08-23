import XCTest

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
        app.buttons["Finalize"].tap()
        let confirmation = app.buttons.matching(identifier: "Finalize").element(boundBy: 1)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 5))
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
