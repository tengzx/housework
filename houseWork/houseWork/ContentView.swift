//
//  ContentView.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var householdStore: HouseholdStore
    @StateObject private var taskBoardStore: TaskBoardStore
    @StateObject private var authStore = AuthStore()
    @StateObject private var tagStore: TagStore
    
    init() {
        let householdStore = HouseholdStore()
        let taskBoardStore = TaskBoardStore(householdStore: householdStore)
        _householdStore = StateObject(wrappedValue: householdStore)
        _taskBoardStore = StateObject(wrappedValue: taskBoardStore)
        _tagStore = StateObject(wrappedValue: TagStore(householdStore: householdStore))
    }
    
    var body: some View {
        Group {
            if authStore.isLoading {
                ProgressView("Loading account…")
            } else if authStore.currentUser == nil {
                LoginView()
            } else {
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
            }
        }
        .environmentObject(householdStore)
        .environmentObject(taskBoardStore)
        .environmentObject(authStore)
        .environmentObject(tagStore)
        .onAppear {
            householdStore.updateUserContext(userId: authStore.firebaseUserId)
        }
        .onChange(of: authStore.firebaseUserId) { newValue in
            householdStore.updateUserContext(userId: newValue)
        }
    }
}

#Preview {
    ContentView()
}
