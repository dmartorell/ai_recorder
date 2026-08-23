import Foundation
import XCTest
@testable import AIRecorder

final class CaptureProofStoreTests: XCTestCase {
    private var rootDirectory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "CaptureProofStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        rootDirectory = nil
    }

    func testPreparingCaptureUsesStableProtectedM4APathAndRecordsActiveState() throws {
        let store = CaptureProofStore(rootDirectory: rootDirectory, defaults: defaults)

        try store.prepareForCapture()

        XCTAssertEqual(store.outputURL.pathExtension, "m4a")
        XCTAssertNotNil(UUID(uuidString: store.outputURL.deletingPathExtension().lastPathComponent))
        XCTAssertTrue(store.captureWasActive)
        XCTAssertNotNil(store.captureStartedAt)

    }

    func testPreparingAnotherCapturePreservesThePreviousOriginalAudio() throws {
        let store = CaptureProofStore(rootDirectory: rootDirectory, defaults: defaults)
        try store.prepareForCapture()
        let previousURL = store.outputURL
        try Data("previous".utf8).write(to: previousURL)

        try store.prepareForCapture()

        XCTAssertNotEqual(store.outputURL, previousURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousURL.path))
        XCTAssertEqual(try Data(contentsOf: previousURL), Data("previous".utf8))
        XCTAssertTrue(store.captureWasActive)
    }

    func testMarkCaptureHandledClearsRecoverySignal() throws {
        let store = CaptureProofStore(rootDirectory: rootDirectory, defaults: defaults)
        try store.prepareForCapture()

        store.markCaptureHandled()

        XCTAssertFalse(store.captureWasActive)
        XCTAssertNil(store.captureStartedAt)
    }
}
