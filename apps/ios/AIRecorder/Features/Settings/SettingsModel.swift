import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored @AppStorage private var storedLanguageCode: String

    var appLanguage: AppLanguage {
        didSet {
            storedLanguageCode = appLanguage.rawValue
        }
    }

    var locale: Locale { appLanguage.locale }

    init(defaults: UserDefaults = .standard) {
        let arguments = ProcessInfo.processInfo.arguments
        let launchLanguage = arguments.indices
            .dropLast()
            .first(where: { arguments[$0] == "-app-language" })
            .flatMap { AppLanguage(rawValue: arguments[$0 + 1]) }
        let language = launchLanguage ?? AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .english
        _storedLanguageCode = AppStorage(
            wrappedValue: AppLanguage.english.rawValue,
            "appLanguage",
            store: defaults
        )
        appLanguage = language
    }
}
