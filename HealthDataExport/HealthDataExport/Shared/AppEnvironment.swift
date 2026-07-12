import Foundation

enum AppEnvironment {
    private static let defaultServerOrigin = URL(string: "https://tengzx-macbookpro11-1.tailff8088.ts.net")!

    static var serverOrigin: URL {
        configuredURL(for: "HEALTHDATAEXPORT_SERVER_ORIGIN") ?? defaultServerOrigin
    }

    static var apiBaseURL: URL {
        serverOrigin.appendingPathComponent("api")
    }

    static var apiV1BaseURL: URL {
        apiBaseURL.appendingPathComponent("v1")
    }

    static var mediaOrigin: String {
        serverOrigin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static var defaultHealthIngestURL: String {
        apiBaseURL.appendingPathComponent("health/ingest").absoluteString
    }

    static func apiURL(_ path: String) -> URL {
        apiBaseURL.appendingPathComponent(path)
    }

    static func apiV1URL(_ path: String) -> URL {
        apiV1BaseURL.appendingPathComponent(path)
    }

    private static func configuredURL(for key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

enum SharedL10n {
    private static let tableDirectories = ["Resources/I18n", ""]
    private static let fallbackLanguage = "zh-Hans"
    private static let languageKey = "app.language"
    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let language = UserDefaults.standard.string(forKey: languageKey) ?? "system"
        let template = lookup(key: key, languageCode: language) ?? lookup(key: key, languageCode: fallbackLanguage) ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale(for: language), arguments: arguments)
    }

    private static func lookup(key: String, languageCode: String) -> String? {
        if languageCode == "system" {
            for code in resolvedSystemLanguages() {
                if let value = dictionary(for: code)?[key] {
                    return value
                }
            }
            return nil
        }
        return dictionary(for: languageCode)?[key]
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
        var resolved: [String] = []
        for candidate in Locale.preferredLanguages {
            if candidate.hasPrefix("zh-Hans") || candidate.hasPrefix("zh") {
                resolved.append("zh-Hans")
            } else if candidate.hasPrefix("en") {
                resolved.append("en")
            }
        }
        resolved.append(contentsOf: ["zh-Hans", "en"])
        var unique: [String] = []
        for code in resolved where !unique.contains(code) {
            unique.append(code)
        }
        return unique
    }

    private static func locale(for languageCode: String) -> Locale {
        switch languageCode {
        case "en":
            return Locale(identifier: "en")
        case "zh-Hans":
            return Locale(identifier: "zh-Hans")
        default:
            return .autoupdatingCurrent
        }
    }
}
