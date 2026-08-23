import Foundation
import XCTest

final class AppConfigurationTests: XCTestCase {
    func testAppDeclaresWhyItNeedsMicrophoneAccess() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String

        XCTAssertNotNil(description)
        XCTAssertFalse(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func testAppDeclaresAudioBackgroundMode() {
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]

        XCTAssertTrue(backgroundModes?.contains("audio") == true)
    }
}
