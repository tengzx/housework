import Foundation

enum AuthAPI {
    static let loginURL = AppEnvironment.apiURL("auth/login")

    static func login(nickname: String, password: String) async throws -> UserSession {
        let body = LoginRequest(nickname: nickname, password: password)
        let response: HTTPClientResponse
        do {
            response = try await HTTPClient.shared.data(url: loginURL, method: .post, body: body)
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                throw AuthError(statusCode: statusCode, message: Self.message(from: data))
            }
            throw error
        }
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: response.data)
        return UserSession(
            userId: decoded.userId,
            nickname: decoded.nickname,
            avatarUrl: decoded.avatarUrl,
            unitSystem: decoded.unitSystem,
            heightCm: decoded.heightCm,
            weightKg: decoded.weightKg,
            preferredLanguage: decoded.preferredLanguage,
            token: decoded.token
        )
    }

    private static func message(from data: Data) -> String {
        if let error = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
            return error.message ?? error.error ?? L10n.tr("auth.login_failed")
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? L10n.tr("auth.login_failed") : raw
    }
}

private struct LoginRequest: Encodable {
    var nickname: String
    var password: String
}

private struct LoginResponse: Decodable {
    var userId: Int
    var nickname: String
    var avatarUrl: String?
    var unitSystem: String?
    var heightCm: Double?
    var weightKg: Double?
    var preferredLanguage: String?
    var token: String
}

private struct AuthErrorResponse: Decodable {
    var error: String?
    var message: String?

    init(from decoder: Decoder) throws {
        // Backend may return {"error": "..."} or {"error": {"message": "..."}} or {"message": "..."}.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode(NestedError.self, forKey: .error) {
            error = nested.code
            message = nested.message
        } else {
            error = try? container.decode(String.self, forKey: .error)
            message = try? container.decode(String.self, forKey: .message)
        }
    }

    private enum CodingKeys: String, CodingKey { case error, message }
    private struct NestedError: Decodable { var code: String?; var message: String? }
}

struct AuthError: LocalizedError {
    var statusCode: Int
    var message: String
    var errorDescription: String? { message }
}
