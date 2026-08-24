import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
}
