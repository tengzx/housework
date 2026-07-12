import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    static let storageKey = "app.language"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .en:
            return Locale(identifier: "en")
        }
    }

    var titleKey: String {
        switch self {
        case .system:
            return "language.option.system"
        case .zhHans:
            return "language.option.zh_hans"
        case .en:
            return "language.option.en"
        }
    }

    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }
}

@MainActor
final class LocalizationStore: ObservableObject {
    private var isApplyingServerLanguage = false

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            guard !isApplyingServerLanguage, AuthTokenStore.token != nil else { return }
            Task {
                try? await UserPreferenceAPI.updatePreferredLanguage(language)
            }
        }
    }

    init() {
        language = AppLanguage.current
    }

    var locale: Locale { language.locale }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalizer.text(key, language: language, arguments: arguments)
    }

    func applyServerLanguage(_ rawValue: String?) {
        guard let rawValue else { return }
        let resolved = AppLanguage(rawValue: rawValue) ?? .system
        UserDefaults.standard.set(resolved.rawValue, forKey: AppLanguage.storageKey)
        guard language != resolved else { return }
        isApplyingServerLanguage = true
        language = resolved
        isApplyingServerLanguage = false
    }
}

enum L10n {
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalizer.text(key, language: AppLanguage.current, arguments: arguments)
    }

    static var currentLanguage: AppLanguage {
        AppLanguage.current
    }

    static var locale: Locale {
        currentLanguage.locale
    }
}

private enum AppLocalizer {
    private static let tableDirectories = ["Resources/I18n", ""]
    private static let fallbackLanguage = "zh-Hans"
    private static let supportedLanguages = ["zh-Hans", "en"]
    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    static func text(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
        let template = lookup(key: key, language: language) ?? lookup(key: key, languageCode: fallbackLanguage) ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: formatLocale(for: language), arguments: arguments)
    }

    private static func lookup(key: String, language: AppLanguage) -> String? {
        switch language {
        case .system:
            for code in resolvedSystemLanguages() {
                if let value = lookup(key: key, languageCode: code) {
                    return value
                }
            }
            return nil
        case .zhHans, .en:
            return lookup(key: key, languageCode: language.rawValue)
        }
    }

    private static func lookup(key: String, languageCode: String) -> String? {
        dictionary(for: languageCode)?[key]
    }

    private static func dictionary(for languageCode: String) -> [String: String]? {
        lock.lock()
        if let cached = cache[languageCode] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resourceURL = tableDirectories.lazy.compactMap { directory -> URL? in
            let subdirectory = directory.isEmpty ? nil : directory
            return Bundle.main.url(forResource: languageCode, withExtension: "json", subdirectory: subdirectory)
        }.first

        guard let url = resourceURL,
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }

        lock.lock()
        cache[languageCode] = dictionary
        lock.unlock()
        return dictionary
    }

    private static func resolvedSystemLanguages() -> [String] {
        let preferred = Locale.preferredLanguages
        var resolved: [String] = []
        for candidate in preferred {
            if candidate.hasPrefix("zh-Hans") || candidate.hasPrefix("zh") {
                resolved.append("zh-Hans")
            } else if candidate.hasPrefix("en") {
                resolved.append("en")
            }
        }
        resolved.append(contentsOf: supportedLanguages)
        var unique: [String] = []
        for code in resolved where !unique.contains(code) {
            unique.append(code)
        }
        return unique
    }

    private static func formatLocale(for language: AppLanguage) -> Locale {
        switch language {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .en:
            return Locale(identifier: "en")
        }
    }
}

private enum UserPreferenceAPI {
    private static let preferredLanguageURL = AppEnvironment.apiV1URL("me/language")

    static func updatePreferredLanguage(_ language: AppLanguage) async throws {
        try await HTTPClient.shared.data(
            url: preferredLanguageURL,
            method: .patch,
            body: UpdatePreferredLanguageRequest(preferredLanguage: language.rawValue)
        )
    }
}

private struct UpdatePreferredLanguageRequest: Encodable {
    let preferredLanguage: String
}
