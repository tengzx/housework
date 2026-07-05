import Foundation

enum AppEnvironment {
    private static let defaultServerOrigin = URL(string: "http://100.67.64.11:8081")!

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
