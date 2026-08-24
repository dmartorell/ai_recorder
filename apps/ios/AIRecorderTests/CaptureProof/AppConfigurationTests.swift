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

    func testAppDeclaresLaunchScreenConfiguration() {
        let launchScreen = appBundle.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any]

        XCTAssertNotNil(launchScreen)
    }

    func testAppRequiresFullScreen() {
        let requiresFullScreen = appBundle.object(forInfoDictionaryKey: "UIRequiresFullScreen") as? Bool

        XCTAssertEqual(requiresFullScreen, true)
    }

    func testAppDeclaresEverySupportedInterfaceOrientation() {
        let orientations = appBundle.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String]

        XCTAssertEqual(
            Set(orientations ?? []),
            [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ]
        )
    }
}
