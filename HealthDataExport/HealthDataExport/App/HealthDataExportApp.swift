import SwiftUI

@main
struct HealthDataExportApp: App {
    @StateObject private var dependencies: AppDependencies
    @StateObject private var localization: LocalizationStore
    @StateObject private var session: SessionStore

    init() {
        let localizationStore = LocalizationStore()
        _dependencies = StateObject(wrappedValue: AppDependencies())
        _localization = StateObject(wrappedValue: localizationStore)
        _session = StateObject(wrappedValue: SessionStore(localizationStore: localizationStore))
        WeChatAuthManager.shared.registerIfNeeded()
    }

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
                            await FocusReminderNotifier.requestAuthorization()
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .environmentObject(localization)
            .environment(\.locale, localization.locale)
            .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
            // WeChat OAuth round-trips through the WeChat app; both callback styles land here.
            .onOpenURL { url in
                WeChatAuthManager.shared.handleOpenURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                WeChatAuthManager.shared.handleUniversalLink(activity)
            }
        }
    }
}
