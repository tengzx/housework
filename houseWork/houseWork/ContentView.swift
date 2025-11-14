//
//  ContentView.swift
//  houseWork
//
//  Created by tengzx on 12.11.2025.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    
    init(
        authStore: AuthStore,
        householdStore: HouseholdStore
    ) {
        _viewModel = StateObject(
            wrappedValue: ContentViewModel(
                authStore: authStore,
                householdStore: householdStore
            )
        )
    }
    
    init() {
        self.init(authStore: AuthStore(), householdStore: HouseholdStore())
    }
    
    var body: some View {
        Group {
            switch viewModel.presentationState {
            case .loadingAccount:
                ProgressView("Loading account…")
            case .authentication:
                LoginView(viewModel: viewModel.loginViewModel)
            case .loadingHousehold:
                ProgressView("Loading household…")
            case .needsHousehold:
                HouseholdSetupView()
            case .dashboard:
                TabView {
                    TaskBoardView(viewModel: viewModel.taskBoardViewModel)
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
        .environmentObject(viewModel.householdStore)
        .environmentObject(viewModel.taskBoardStore)
        .environmentObject(viewModel.authStore)
        .environmentObject(viewModel.tagStore)
        .onAppear {
            viewModel.onAppear()
        }
    }
}

#Preview {
    ContentView()
}
    
