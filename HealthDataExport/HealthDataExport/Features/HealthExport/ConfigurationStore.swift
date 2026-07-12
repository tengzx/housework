import Foundation
import Combine

@MainActor
final class ConfigurationStore: ObservableObject {
    static let shared = ConfigurationStore()

    @Published private(set) var configurations: [ExportConfiguration] = []

    private let defaults: UserDefaults
    nonisolated static let storageKey = "export.configurations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            configurations = [ExportConfiguration()]
            save()
            return
        }
        do {
            configurations = try JSONDecoder().decode([ExportConfiguration].self, from: data)
            let migratedLegacyTokens = migrateLegacyTokensIfNeeded()
            if configurations.isEmpty {
                configurations = [ExportConfiguration()]
                save()
            } else {
                migrateIfNeeded()
                if migratedLegacyTokens { save() }
            }
        } catch {
            configurations = [ExportConfiguration(lastStatus: L10n.tr("health_export.config_load_reset"))]
            save()
        }
    }

    private func migrateIfNeeded() {
        let defaultURL = AppEnvironment.defaultHealthIngestURL
        var changed = false
        for i in configurations.indices where configurations[i].endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configurations[i].endpointURL = defaultURL
            changed = true
        }
        if changed { save() }
    }

    private func migrateLegacyTokensIfNeeded() -> Bool {
        var migrated = false
        for i in configurations.indices {
            let legacyToken = configurations[i].bearerToken
            if legacyToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configurations[i].bearerToken = KeychainTokenStore.token(for: configurations[i].id)
            } else {
                KeychainTokenStore.saveToken(legacyToken, for: configurations[i].id)
                migrated = true
            }
        }
        return migrated
    }

    func save() {
        configurations.forEach { KeychainTokenStore.saveToken($0.bearerToken, for: $0.id) }
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func addConfiguration() -> ExportConfiguration {
        let config = ExportConfiguration(name: L10n.tr("health_export.default_config_name", configurations.count + 1))
        configurations.append(config)
        save()
        return config
    }

    func update(_ configuration: ExportConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
        save()
    }

    func delete(_ configuration: ExportConfiguration) {
        KeychainTokenStore.saveToken("", for: configuration.id)
        configurations.removeAll { $0.id == configuration.id }
        if configurations.isEmpty {
            configurations.append(ExportConfiguration())
        }
        save()
    }

    func configuration(id: UUID) -> ExportConfiguration? {
        configurations.first { $0.id == id }
    }

    func markSent(id: UUID, status: String, at date: Date = .now) {
        guard let index = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[index].lastSentAt = date
        configurations[index].lastStatus = status
        save()
    }
}
