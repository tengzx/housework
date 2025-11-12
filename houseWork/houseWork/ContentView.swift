//
//  ContentView.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var taskBoardStore = TaskBoardStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var tagStore = TagStore()
    
    var body: some View {
        TabView {
            TaskBoardView()
                .tabItem {
                    Label("Board", systemImage: "rectangle.grid.2x2")
                }
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
            ChoreCatalogView()
                .tabItem {
                    Label("Catalog", systemImage: "list.bullet.rectangle")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(taskBoardStore)
        .environmentObject(authStore)
        .environmentObject(tagStore)
    }
}

#Preview {
    ContentView()
}
