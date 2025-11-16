//
//  RewardsViewModel.swift
//  houseWork
//
//  Coordinates reward catalog display and redemption intents.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class RewardsViewModel: ObservableObject {
    struct AlertContext: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let message: String
    }
    
    @Published private(set) var catalog: [RewardItem] = []
    @Published private(set) var history: [RewardRedemption] = []
    @Published private(set) var availablePoints: Int = 0
    @Published private(set) var lifetimePoints: Int = 0
    @Published private(set) var isRedeeming: Bool = false
    @Published var activeAlert: AlertContext?
    
    private let rewardsStore: RewardsStore
    private let authStore: AuthStore
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        rewardsStore: RewardsStore,
        authStore: AuthStore
    ) {
        self.rewardsStore = rewardsStore
        self.authStore = authStore
        bind()
        recalculatePoints()
    }
    
    var currentMemberName: String {
        authStore.currentUser?.name ?? ""
    }
    
    func redeem(_ reward: RewardItem) async {
        guard let member = authStore.currentUser else {
            activeAlert = AlertContext(
                title: LocalizedStringKey("rewards.alert.error"),
                message: String(localized: "rewards.error.noMember")
            )
            return
        }
        guard availablePoints >= reward.cost else {
            activeAlert = AlertContext(
                title: LocalizedStringKey("rewards.alert.error"),
                message: String(localized: "rewards.error.insufficientPoints")
            )
            return
        }
        guard !isRedeeming else { return }
        isRedeeming = true
        let success = await rewardsStore.redeem(reward, by: member)
        isRedeeming = false
        if success {
            let rewardName = reward.name
            let template = NSLocalizedString("rewards.success.redeemed", comment: "")
            await authStore.adjustPoints(availableDelta: -reward.cost)
            activeAlert = AlertContext(
                title: LocalizedStringKey("rewards.alert.success"),
                message: String(format: template, rewardName)
            )
        } else {
            let fallback = String(localized: "rewards.error.generic")
            activeAlert = AlertContext(
                title: LocalizedStringKey("rewards.alert.error"),
                message: rewardsStore.error ?? fallback
            )
        }
    }
    
    func canRedeem(_ reward: RewardItem) -> Bool {
        availablePoints >= reward.cost && !isRedeeming
    }
    
    func dismissAlert() {
        activeAlert = nil
    }
    
    private func bind() {
        rewardsStore.$catalog
            .receive(on: DispatchQueue.main)
            .assign(to: &$catalog)
        
        rewardsStore.$redemptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] redemptions in
                guard let self else { return }
                self.history = redemptions
                self.recalculatePoints()
            }
            .store(in: &cancellables)
        
        authStore.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculatePoints()
            }
            .store(in: &cancellables)
        
        authStore.$userProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculatePoints()
            }
            .store(in: &cancellables)
    }
    
    private func recalculatePoints() {
        guard let member = authStore.currentUser else {
            availablePoints = 0
            lifetimePoints = 0
            return
        }
        let profilePoints = authStore.userProfile?.points ?? 0
        let lifetime = authStore.userProfile?.lifetimePoints ?? profilePoints
        let spent = rewardsStore.redemptions
            .filter { $0.memberId == member.id }
            .reduce(0) { $0 + $1.cost }
        availablePoints = max(0, profilePoints)
        lifetimePoints = max(0, lifetime)
    }
}
