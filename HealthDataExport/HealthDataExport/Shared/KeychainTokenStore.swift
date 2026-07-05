import Foundation
import Security

enum KeychainTokenStore {
    private static let service = "com.tengzx.HealthDataExport.tokens"

    static func token(for id: UUID) -> String {
        (try? read(account: account(for: id))) ?? ""
    }

    static func saveToken(_ token: String, for id: UUID) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = account(for: id)
        if trimmed.isEmpty {
            try? delete(account: account)
        } else {
            try? save(trimmed, account: account)
        }
    }

    private static func account(for id: UUID) -> String {
        "export-configuration-\(id.uuidString)"
    }

    private static func read(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct KeychainError: Error {
    let status: OSStatus
}
