import Foundation

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
            return "接口没有返回有效 HTTP 响应。"
        case let .httpFailure(statusCode, data):
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.isEmpty ? "接口请求失败 (\(statusCode))" : "接口请求失败 (\(statusCode))：\(body)"
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
