import Combine
import Foundation

/// The authenticated user's profile plus the bearer token used for all API calls.
struct UserSession: Codable, Equatable {
    var userId: Int
    var nickname: String
    var avatarUrl: String?
    var unitSystem: String?
    var heightCm: Double?
    var weightKg: Double?
    var preferredLanguage: String?
    var token: String
}

/// Persists the session: token in the Keychain, profile in UserDefaults.
private enum SessionPersistence {
    private static let service = "com.tengzx.HealthDataExport.auth"
    private static let account = "current-session-token"
    private static let profileKey = "auth.session.profile"

    static func load() -> UserSession? {
        guard var session = loadProfile() else { return nil }
        let token = readToken() ?? ""
        guard !token.isEmpty else { return nil }
        session.token = token
        return session
    }

    static func save(_ session: UserSession) {
        saveToken(session.token)
        var profile = session
        profile.token = "" // never persist the token in UserDefaults
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    static func clear() {
        saveToken("")
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    private static func loadProfile() -> UserSession? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let updated = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// App-wide authentication state. Owns the session, keeps `AuthTokenStore` in sync
/// so every API request carries the bearer token, and drives the login gate.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: UserSession?
    private weak var localizationStore: LocalizationStore?

    var isAuthenticated: Bool { session != nil }
    var currentUserId: Int? { session?.userId }

    init(localizationStore: LocalizationStore? = nil) {
        self.localizationStore = localizationStore
        let restored = SessionPersistence.load()
        session = restored
        AuthTokenStore.set(restored?.token)
        localizationStore?.applyServerLanguage(restored?.preferredLanguage)
        // Bridge the token to the paired Apple Watch so it can authenticate too.
        PhoneWatchSync.shared.activate()
        pushToWatch(restored)
        // Log out automatically if the server rejects our token mid-flight.
        HTTPClient.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.logout() }
        }
    }

    private func pushToWatch(_ session: UserSession?) {
        PhoneWatchSync.shared.updateSession(
            token: session?.token,
            userId: session?.userId,
            nickname: session?.nickname
        )
    }

    func login(nickname: String, password: String) async throws {
        let newSession = try await AuthAPI.login(nickname: nickname, password: password)
        apply(newSession)
    }

    func apply(_ newSession: UserSession) {
        AuthTokenStore.set(newSession.token)
        SessionPersistence.save(newSession)
        session = newSession
        localizationStore?.applyServerLanguage(newSession.preferredLanguage)
        pushToWatch(newSession)
    }

    func logout() {
        AuthTokenStore.set(nil)
        SessionPersistence.clear()
        session = nil
        pushToWatch(nil)
    }
}
