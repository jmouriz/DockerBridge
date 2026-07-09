import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case system
    case english = "en"
    case spanish = "es"

    static func normalized(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }

    var code: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.tr("language.system")
        case .english:
            return L10n.tr("language.english")
        case .spanish:
            return L10n.tr("language.spanish")
        }
    }
}

enum L10n {
    private static var language: AppLanguage = .system
    private static let fallbackLanguageCode = "en"
    private static let supportedLanguageCodes = ["en", "es"]

    static var activeLanguageCode: String {
        switch language {
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .system:
            return systemLanguageCode()
        }
    }

    static func configure(languageCode: String) {
        language = AppLanguage.normalized(languageCode)
    }

    static func tr(_ key: String) -> String {
        localizedString(forKey: key, languageCode: activeLanguageCode)
            ?? localizedString(forKey: key, languageCode: fallbackLanguageCode)
            ?? key
    }

    static func trf(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: tr(key),
            locale: Locale(identifier: activeLanguageCode),
            arguments: arguments
        )
    }

    static func localizedResourceURL(forResource name: String, withExtension fileExtension: String) -> URL? {
        let languageCodes = unique([activeLanguageCode, fallbackLanguageCode])

        for languageCode in languageCodes {
            if let localizedURL = Bundle.main.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: nil,
                localization: languageCode
            ) {
                return localizedURL
            }
        }

        return Bundle.main.url(forResource: name, withExtension: fileExtension)
    }

    private static func localizedString(forKey key: String, languageCode: String) -> String? {
        guard
            let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return nil
        }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }

    private static func systemLanguageCode() -> String {
        for preferredLanguage in Locale.preferredLanguages {
            let normalized = preferredLanguage.lowercased()
            if normalized.hasPrefix("es") {
                return "es"
            }
            if normalized.hasPrefix("en") {
                return "en"
            }
        }

        return fallbackLanguageCode
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { supportedLanguageCodes.contains($0) && seen.insert($0).inserted }
    }
}
