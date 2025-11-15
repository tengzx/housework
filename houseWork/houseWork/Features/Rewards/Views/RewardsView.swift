//
//  RewardsView.swift
//  houseWork
//
//  Presents the reward catalog and redemption history.
//

import SwiftUI

struct RewardsView: View {
    @StateObject private var viewModel: RewardsViewModel
    
    init(viewModel: RewardsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        navigationContainer {
            List {
                Section {
                    PointsSummaryView(
                        availablePoints: viewModel.availablePoints,
                        lifetimePoints: viewModel.lifetimePoints
                    )
                }
                
                Section(header: Text(LocalizedStringKey("rewards.section.catalog"))) {
                    if viewModel.catalog.isEmpty {
                        Text(LocalizedStringKey("rewards.catalog.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.catalog) { reward in
                            RewardRow(
                                reward: reward,
                                canRedeem: viewModel.canRedeem(reward)
                            ) {
                                Haptics.impact()
                                Task {
                                    await viewModel.redeem(reward)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text(LocalizedStringKey("rewards.section.history"))) {
                    if viewModel.history.isEmpty {
                        Text(LocalizedStringKey("rewards.history.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.history.prefix(10)) { redemption in
                            RedemptionRow(redemption: redemption)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(LocalizedStringKey("rewards.title"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(item: $viewModel.activeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(LocalizedStringKey("common.ok"))) {
                        viewModel.dismissAlert()
                    }
                )
            }
        }
    }
}

private struct PointsSummaryView: View {
    let availablePoints: Int
    let lifetimePoints: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("rewards.header.title"))
                .font(.headline)
            HStack(spacing: 12) {
                SummaryCard(
                    titleKey: "rewards.header.available",
                    subtitleKey: "rewards.header.available.subtitle",
                    value: availablePoints,
                    gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.5)])
                )
                SummaryCard(
                    titleKey: "rewards.header.lifetime",
                    subtitleKey: "rewards.header.lifetime.subtitle",
                    value: lifetimePoints,
                    gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.purple.opacity(0.5)])
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }
}

private struct SummaryCard: View {
    let titleKey: String
    let subtitleKey: String
    let value: Int
    let gradient: Gradient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            Text("\(value)")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text(LocalizedStringKey(subtitleKey))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .cornerRadius(16)
        )
    }
}

private struct RewardRow: View {
    let reward: RewardItem
    let canRedeem: Bool
    let redeemAction: () -> Void
    
    private var costText: String {
        String(format: String(localized: "rewards.cost.format"), reward.cost)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.name)
                        .font(.headline)
                }
                Spacer()
                Text(costText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                redeemAction()
            } label: {
                Text(LocalizedStringKey("rewards.redeem.button"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRedeem)
        }
        .padding(.vertical, 8)
    }
}

private struct RedemptionRow: View {
    let redemption: RewardRedemption
    
    private var costText: String {
        String(format: String(localized: "rewards.cost.format"), redemption.cost)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(redemption.rewardName)
                    .font(.headline)
                Text(
                    String(
                        format: String(localized: "rewards.history.entry"),
                        redemption.memberName,
                        redemption.cost
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(costText)
                    .font(.headline)
                Text(redemption.redeemedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let session = AuthSession(userId: "preview-user", displayName: "Jordan", email: "preview@example.com")
    let memberId = UUID()
    let profile = UserProfile(
        id: session.userId,
        name: "Jordan Preview",
        email: session.email ?? "",
        accentColor: .blue,
        memberId: memberId.uuidString,
        points: 250
    )
    let authStore = AuthStore(
        authService: InMemoryAuthenticationService(initialSession: session),
        profileService: InMemoryUserProfileService(seedProfiles: [session.userId: profile])
    )
    let rewardsStore = RewardsStore(
        previewCatalog: RewardItem.sampleCatalog,
        previewRedemptions: RewardRedemption.sample(memberId: memberId)
    )
    return RewardsView(
        viewModel: RewardsViewModel(
            rewardsStore: rewardsStore,
            authStore: authStore
        )
    )
}
