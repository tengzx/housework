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
    @StateObject private var languageStore = LanguageStore()
    
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
                ProgressView(LocalizedStringKey("loading.account"))
            case .authentication:
                LoginView(viewModel: viewModel.loginViewModel)
            case .loadingHousehold:
                ProgressView(LocalizedStringKey("loading.household"))
            case .needsHousehold:
                HouseholdSetupView()
            case .dashboard:
                TabView {
                    TaskBoardView(viewModel: viewModel.taskBoardViewModel)
                        .tabItem {
                            Label(LocalizedStringKey("tabs.board"), systemImage: "rectangle.grid.2x2")
                        }
                    AnalyticsView()
                        .tabItem {
                            Label(LocalizedStringKey("tabs.analytics"), systemImage: "chart.line.uptrend.xyaxis")
                        }
                    ChoreCatalogView()
                        .tabItem {
                            Label(LocalizedStringKey("tabs.catalog"), systemImage: "list.bullet.rectangle")
                        }
                    SettingsView()
                        .tabItem {
                            Label(LocalizedStringKey("tabs.settings"), systemImage: "gear")
                        }
                }
            }
        }
        .environmentObject(viewModel.householdStore)
        .environmentObject(viewModel.taskBoardStore)
        .environmentObject(viewModel.authStore)
        .environmentObject(viewModel.tagStore)
        .environmentObject(languageStore)
        .environment(\.locale, languageStore.locale)
        .onAppear {
            viewModel.onAppear()
        }
    }
}

#Preview {
    ContentView()
}
    
