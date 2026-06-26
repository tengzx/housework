//
//  HealthDataExportApp.swift
//  HealthDataExport
//
//  Created by tengzx on 8.6.2026.
//

import SwiftUI

@main
struct HealthDataExportApp: App {
    @StateObject private var observerSyncManager = HealthObserverSyncManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    observerSyncManager.start()
                }
        }
    }
}
