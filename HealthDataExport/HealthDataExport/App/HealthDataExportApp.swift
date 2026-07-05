import SwiftUI

@main
struct HealthDataExportApp: App {
    @StateObject private var dependencies = AppDependencies()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isAuthenticated {
                    ContentView()
                        .environmentObject(dependencies)
                        .environmentObject(dependencies.configurationStore)
                        .environmentObject(dependencies.healthObserverSyncManager)
                        .environmentObject(dependencies.fitnessSessionEvents)
                        .task {
                            dependencies.healthObserverSyncManager.start()
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        }
    }
}
