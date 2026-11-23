import Foundation

/// Applies the UI-language preference.
///
/// Must run before anything reads localized resources (first thing in `main.swift`).
/// The choice is written to the volatile *argument* domain, so it affects only this
/// process and never overrides the user's system language permanently.
enum AppLanguage {
    /// Localization code actually used by this process ("ja" or "en").
    private(set) static var activeCode = "en"

    static func applyAtLaunch(defaults: UserDefaults = AppRuntime.defaults) {
        let setting = AppLanguageSetting(rawValue: defaults.string(forKey: SettingsKey.language) ?? "") ?? .system
        // The unit-test host always follows English for "System" so assertions on UI strings do not
        // depend on the developer's system language (Japanese is verified through ja.lproj directly).
        let preferred = AppRuntime.isUnitTestHost ? ["en"] : Locale.preferredLanguages
        let code = resolve(setting, preferred: preferred)
        activeCode = code
        // Bundle localization reads AppleLanguages from the standard defaults' argument domain.
        let standard = UserDefaults.standard
        var args = standard.volatileDomain(forName: UserDefaults.argumentDomain)
        args["AppleLanguages"] = [code]
        standard.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    }

    /// "System" means Japanese if the user's first preferred language is Japanese, English otherwise.
    nonisolated static func resolve(_ setting: AppLanguageSetting, preferred: [String]) -> String {
        switch setting {
        case .japanese: return "ja"
        case .english: return "en"
        case .system: return (preferred.first?.lowercased().hasPrefix("ja") ?? false) ? "ja" : "en"
        }
    }
}
