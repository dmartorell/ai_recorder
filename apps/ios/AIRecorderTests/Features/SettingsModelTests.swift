import Foundation
import XCTest
@testable import AIRecorder

@MainActor
final class SettingsModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLanguagesMapToSupportedLocales() {
        XCTAssertEqual(AppLanguage.spanish.locale.language.languageCode?.identifier, "es")
        XCTAssertEqual(AppLanguage.english.locale.language.languageCode?.identifier, "en")
    }

    func testLanguagePersistsAcrossModelRecreation() {
        let settings = SettingsModel(defaults: defaults)
        settings.appLanguage = .spanish

        XCTAssertEqual(SettingsModel(defaults: defaults).appLanguage, .spanish)
    }

    func testFallbackTitleRelocalizesAndCustomTitleIsPreserved() {
        let item = AudioItem(
            startedAt: Date(timeIntervalSince1970: 1_777_777_777),
            fileName: "source.m4a"
        )

        let spanishTitle = item.displayTitle(locale: .init(identifier: "es_ES"), timeZone: .gmt)
        let englishTitle = item.displayTitle(locale: .init(identifier: "en_US"), timeZone: .gmt)

        XCTAssertFalse(spanishTitle.contains("Audio -"))
        XCTAssertFalse(englishTitle.contains("Recording -"))
        XCTAssertNotEqual(spanishTitle, englishTitle)

        item.customTitle = "Entrevista de campo"
        XCTAssertEqual(item.displayTitle(locale: .init(identifier: "en_US"), timeZone: .gmt), "Entrevista de campo")
        XCTAssertEqual(item.displayTitle(locale: .init(identifier: "es_ES"), timeZone: .gmt), "Entrevista de campo")
    }

}
