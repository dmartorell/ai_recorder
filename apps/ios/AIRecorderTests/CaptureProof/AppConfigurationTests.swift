import Foundation
import XCTest

final class AppConfigurationTests: XCTestCase {
    private var appBundle: Bundle {
        let testBundle = Bundle(for: Self.self)
        let appURL = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Bundle(url: appURL) ?? Bundle.main
    }

    func testAppDeclaresWhyItNeedsMicrophoneAccess() {
        let description = appBundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String

        XCTAssertNotNil(description)
        XCTAssertFalse(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func testAppDeclaresAudioBackgroundMode() {
        let backgroundModes = appBundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]

        XCTAssertTrue(backgroundModes?.contains("audio") == true)
    }
}
