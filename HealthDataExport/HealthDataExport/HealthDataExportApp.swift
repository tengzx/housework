import SwiftUI

@main
struct HealthDataExportApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    HealthObserverSyncManager.shared.start()
                }
        }
    }
}
