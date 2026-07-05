import Combine
import Foundation

@MainActor
final class FitnessSessionEventStore: ObservableObject {
    @Published private(set) var completedSessionVersion = 0

    func sessionDidComplete() {
        completedSessionVersion += 1
    }
}

@MainActor
final class AppDependencies: ObservableObject {
    let configurationStore: ConfigurationStore
    let healthObserverSyncManager: HealthObserverSyncManager
    let fitnessSessionEvents: FitnessSessionEventStore

    init() {
        let configurationStore = ConfigurationStore()
        let fitnessSessionEvents = FitnessSessionEventStore()
        self.configurationStore = configurationStore
        self.fitnessSessionEvents = fitnessSessionEvents
        self.healthObserverSyncManager = HealthObserverSyncManager(configurationStore: configurationStore)
    }

    init(configurationStore: ConfigurationStore, fitnessSessionEvents: FitnessSessionEventStore) {
        self.configurationStore = configurationStore
        self.fitnessSessionEvents = fitnessSessionEvents
        self.healthObserverSyncManager = HealthObserverSyncManager(configurationStore: configurationStore)
    }
}
