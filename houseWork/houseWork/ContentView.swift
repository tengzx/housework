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
                LoadingSplashView(message: LocalizedStringKey("loading.account"))
            case .authentication:
                if viewModel.authStore.isProcessing {
                    LoadingSplashView(message: LocalizedStringKey("loading.account"))
                } else {
                    LoginView(viewModel: viewModel.loginViewModel)
                }
            case .loadingHousehold:
                LoadingSplashView(message: LocalizedStringKey("loading.household"))
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
                    RewardsView(viewModel: viewModel.rewardsViewModel)
                        .tabItem {
                            Label(LocalizedStringKey("tabs.rewards"), systemImage: "gift.fill")
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
        .environmentObject(viewModel.memberDirectory)
        .environmentObject(viewModel.rewardsStore)
        .environmentObject(languageStore)
        .environment(\.locale, languageStore.locale)
        .onAppear {
            viewModel.onAppear()
        }
    }
}

private struct LoadingSplashView: View {
    let message: LocalizedStringKey
    
    var body: some View {
        ZStack {
            Image("loading")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

#Preview {
    ContentView()
}
    
