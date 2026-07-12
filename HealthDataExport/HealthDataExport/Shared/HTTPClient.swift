import Foundation

private enum HTTPClientStrings {
    private static let tableDirectory = "Resources/I18n"
    private static let fallbackLanguage = "zh-Hans"
    private static let supportedLanguages = ["zh-Hans", "en"]
    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = UserDefaults.standard.string(forKey: "app.language") ?? "system"
        let template = lookup(key: key, languageCode: language) ?? lookup(key: key, languageCode: fallbackLanguage) ?? fallback(for: key)
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale(for: language), arguments: arguments)
    }

    private static func lookup(key: String, languageCode: String) -> String? {
        switch languageCode {
        case "system":
            for code in resolvedSystemLanguages() {
                if let value = dictionary(for: code)?[key] {
                    return value
                }
            }
            return nil
        default:
            return dictionary(for: languageCode)?[key]
        }
    }

    private static func dictionary(for languageCode: String) -> [String: String]? {
        lock.lock()
        if let cached = cache[languageCode] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: languageCode, withExtension: "json", subdirectory: tableDirectory),
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
        resolved.append(contentsOf: supportedLanguages)
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

    private static func fallback(for key: String) -> String {
        switch key {
        case "http.invalid_response":
            return "The server did not return a valid HTTP response."
        case "http.request_failed":
            return "Request failed (%d)"
        case "http.request_failed_with_body":
            return "Request failed (%d): %@"
        default:
            return key
        }
    }
}

/// Thread-safe holder for the current bearer token. `HTTPClient` reads this
/// synchronously when building requests, so it must be accessible off the main
/// actor (and from any target that compiles `HTTPClient`). `SessionStore` keeps
/// it in sync with the logged-in session.
enum AuthTokenStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _token: String?

    static var token: String? {
        lock.lock(); defer { lock.unlock() }
        return _token
    }

    static func set(_ token: String?) {
        lock.lock()
        _token = token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : token
        lock.unlock()
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct HTTPClientResponse {
    let data: Data
    let httpResponse: HTTPURLResponse

    var statusCode: Int {
        httpResponse.statusCode
    }

    var responseBody: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

enum HTTPClientError: LocalizedError {
    case invalidResponse
    case httpFailure(statusCode: Int, data: Data)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return HTTPClientStrings.text("http.invalid_response")
        case let .httpFailure(statusCode, data):
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.isEmpty
                ? HTTPClientStrings.text("http.request_failed", statusCode)
                : HTTPClientStrings.text("http.request_failed_with_body", statusCode, body)
        }
    }
}

struct HTTPClient {
    static let shared = HTTPClient()

    /// Invoked whenever a request comes back 401. Used to drop the session and
    /// return the user to the login screen. Set by `SessionStore`.
    nonisolated(unsafe) static var onUnauthorized: (() -> Void)?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> HTTPClientResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                Self.onUnauthorized?()
            }
            throw HTTPClientError.httpFailure(statusCode: httpResponse.statusCode, data: data)
        }
        return HTTPClientResponse(data: data, httpResponse: httpResponse)
    }

    func data<Body: Encodable>(
        url: URL,
        method: HTTPMethod,
        body: Body? = Optional<String>.none,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        timeoutInterval: TimeInterval? = nil
    ) async throws -> HTTPClientResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        // Attach the auth bearer token for API calls, unless the caller already
        // set an Authorization header (e.g. Health Export's per-config token).
        if request.value(forHTTPHeaderField: "Authorization") == nil,
           let token = AuthTokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await data(for: request)
    }

    func decode<T: Decodable, Body: Encodable>(
        _ type: T.Type,
        url: URL,
        method: HTTPMethod,
        body: Body? = Optional<String>.none,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        timeoutInterval: TimeInterval? = nil
    ) async throws -> T {
        let response = try await data(
            url: url,
            method: method,
            body: body,
            headers: headers,
            encoder: encoder,
            timeoutInterval: timeoutInterval
        )
        return try decoder.decode(T.self, from: response.data)
    }
}
