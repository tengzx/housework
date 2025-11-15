//
//  RewardsStore.swift
//  houseWork
//
//  Manages the local reward catalog and redemption ledger per household.
//

import Foundation
import Combine

protocol RewardCatalogService {
    func loadCatalog() async throws -> [RewardItem]
}

protocol RewardLedgerService {
    func loadRedemptions(for householdId: String) throws -> [RewardRedemption]
    func save(redemptions: [RewardRedemption], for householdId: String) throws
}

@MainActor
final class RewardsStore: ObservableObject {
    @Published private(set) var catalog: [RewardItem]
    @Published private(set) var redemptions: [RewardRedemption]
    @Published var error: String?
    @Published private(set) var isLoading: Bool
    @Published private(set) var isProcessing: Bool = false
    
    private let catalogService: RewardCatalogService
    private let ledgerService: RewardLedgerService
    private weak var householdStore: HouseholdStore?
    private var householdCancellable: AnyCancellable?
    private var currentHouseholdId: String = ""
    private let isPreviewMode: Bool
    
    init(
        householdStore: HouseholdStore,
        catalogService: RewardCatalogService = StaticRewardCatalogService(),
        ledgerService: RewardLedgerService = UserDefaultsRewardLedgerService()
    ) {
        self.householdStore = householdStore
        self.catalogService = catalogService
        self.ledgerService = ledgerService
        self.catalog = []
        self.redemptions = []
        self.isLoading = true
        self.isPreviewMode = false
        self.currentHouseholdId = householdStore.householdId
        loadCatalog()
        observeHouseholds(store: householdStore)
        Task { @MainActor in
            await loadLedger(for: householdStore.householdId)
        }
    }
    
    init(previewCatalog: [RewardItem] = RewardItem.sampleCatalog, previewRedemptions: [RewardRedemption] = []) {
        self.catalogService = StaticRewardCatalogService(catalog: previewCatalog)
        self.ledgerService = InMemoryRewardLedgerService()
        self.catalog = previewCatalog
        self.redemptions = previewRedemptions
        self.isLoading = false
        self.isPreviewMode = true
        self.currentHouseholdId = "preview-household"
    }
    
    deinit {
        householdCancellable?.cancel()
    }
    
    private func observeHouseholds(store: HouseholdStore) {
        householdCancellable = store.$householdId
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self else { return }
                Task { @MainActor in
                    await self.switchHousehold(to: id)
                }
            }
    }
    
    private func loadCatalog() {
        Task {
            do {
                let items = try await catalogService.loadCatalog()
                await MainActor.run {
                    self.catalog = items.sorted { $0.cost < $1.cost }
                    self.isLoading = false
                    self.error = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func switchHousehold(to newId: String) async {
        guard !isPreviewMode else { return }
        currentHouseholdId = newId
        await loadLedger(for: newId)
    }
    
    private func loadLedger(for householdId: String) async {
        guard !isPreviewMode else { return }
        if householdId.isEmpty {
            redemptions = []
            return
        }
        do {
            let stored = try ledgerService.loadRedemptions(for: householdId)
            redemptions = stored.sorted { $0.redeemedAt > $1.redeemedAt }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @discardableResult
    func redeem(_ reward: RewardItem, by member: HouseholdMember) async -> Bool {
        guard !isProcessing else { return false }
        let newRedemption = RewardRedemption(
            rewardId: reward.id,
            rewardTitleKey: reward.titleKey,
            memberId: member.id,
            memberName: member.name,
            cost: reward.cost
        )
        isProcessing = true
        defer { isProcessing = false }
        
        if isPreviewMode {
            redemptions.insert(newRedemption, at: 0)
            return true
        }
        
        guard !currentHouseholdId.isEmpty else {
            error = String(localized: "rewards.error.missingHousehold")
            return false
        }
        
        let updated = [newRedemption] + redemptions
        do {
            try ledgerService.save(redemptions: updated, for: currentHouseholdId)
            redemptions = updated
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct StaticRewardCatalogService: RewardCatalogService {
    var catalog: [RewardItem]
    
    init(catalog: [RewardItem] = RewardItem.sampleCatalog) {
        self.catalog = catalog
    }
    
    func loadCatalog() async throws -> [RewardItem] {
        catalog
    }
}

final class UserDefaultsRewardLedgerService: RewardLedgerService {
    private let defaults: UserDefaults
    private let keyPrefix = "rewards.ledger."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func loadRedemptions(for householdId: String) throws -> [RewardRedemption] {
        guard let data = defaults.data(forKey: keyPrefix + householdId) else {
            return []
        }
        return try decoder.decode([RewardRedemption].self, from: data)
    }
    
    func save(redemptions: [RewardRedemption], for householdId: String) throws {
        let data = try encoder.encode(redemptions)
        defaults.set(data, forKey: keyPrefix + householdId)
    }
}

final class InMemoryRewardLedgerService: RewardLedgerService {
    private var storage: [String: [RewardRedemption]] = [:]
    
    func loadRedemptions(for householdId: String) throws -> [RewardRedemption] {
        storage[householdId] ?? []
    }
    
    func save(redemptions: [RewardRedemption], for householdId: String) throws {
        storage[householdId] = redemptions
    }
}
