import Foundation
import Combine

@MainActor
final class ConfigurationStore: ObservableObject {
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
            if configurations.isEmpty {
                configurations = [ExportConfiguration()]
                save()
            }
        } catch {
            configurations = [ExportConfiguration(lastStatus: "配置读取失败，已重置")]
            save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func addConfiguration() -> ExportConfiguration {
        let config = ExportConfiguration(name: "接口 \(configurations.count + 1)")
        configurations.append(config)
        save()
        notifyObserverSyncChanged()
        return config
    }

    func update(_ configuration: ExportConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
        save()
        notifyObserverSyncChanged()
    }

    func delete(_ configuration: ExportConfiguration) {
        configurations.removeAll { $0.id == configuration.id }
        if configurations.isEmpty {
            configurations.append(ExportConfiguration())
        }
        save()
        notifyObserverSyncChanged()
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

    private func notifyObserverSyncChanged() {
        Task {
            HealthObserverSyncManager.shared.configurationDidChange()
        }
    }
}

enum ConfigurationPersistence {
    nonisolated static func load(defaults: UserDefaults = .standard) -> [ExportConfiguration] {
        guard let data = defaults.data(forKey: ConfigurationStore.storageKey),
              let configurations = try? JSONDecoder().decode([ExportConfiguration].self, from: data) else {
            return []
        }
        return configurations
    }

    nonisolated static func save(_ configurations: [ExportConfiguration], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: ConfigurationStore.storageKey)
    }

    nonisolated static func markSent(id: UUID, status: String, at date: Date = .now, defaults: UserDefaults = .standard) {
        var configurations = load(defaults: defaults)
        guard let index = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[index].lastSentAt = date
        configurations[index].lastStatus = status
        save(configurations, defaults: defaults)
    }
}
