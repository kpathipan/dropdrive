import Foundation
import Observation

/// In-app language switch (English/Thai), independent of the system locale so
/// it takes effect immediately from Preferences — no restart, no System
/// Settings trip. Views read it through `tr(_:_:)`, which registers Observation
/// tracking, so every visible string re-renders the moment the code changes.
@Observable
final class AppLanguage {
    static let shared = AppLanguage()

    static let english = "en"
    static let thai = "th"

    var code: String {
        didSet { UserDefaults.standard.set(code, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "appLanguageCode"

    private init() {
        code = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? Self.english
    }
}

/// Returns the Thai string when Thai is selected, the English one otherwise.
func tr(_ english: String, _ thai: String) -> String {
    AppLanguage.shared.code == AppLanguage.thai ? thai : english
}
