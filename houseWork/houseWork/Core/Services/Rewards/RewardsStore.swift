//
//  RewardsStore.swift
//  houseWork
//
//  Manages the local reward catalog and redemption ledger per household.
//

import Foundation
import Combine

protocol RewardCatalogService {
    func observeCatalog(for householdId: String, handler: @escaping (Result<[RewardItem], Error>) -> Void) -> ListenerToken
    func addReward(_ reward: RewardItem, to householdId: String) async throws
    func deleteReward(_ reward: RewardItem, from householdId: String) async throws
}

protocol RewardLedgerService {
    func observeRedemptions(for householdId: String, handler: @escaping (Result<[RewardRedemption], Error>) -> Void) -> ListenerToken
    func addRedemption(_ redemption: RewardRedemption, householdId: String) async throws
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
    private var catalogListener: ListenerToken?
    private var ledgerListener: ListenerToken?
    private let isPreviewMode: Bool
    
    init(
        householdStore: HouseholdStore,
        catalogService: RewardCatalogService = FirestoreRewardCatalogService(),
        ledgerService: RewardLedgerService = FirestoreRewardLedgerService()
    ) {
        self.householdStore = householdStore
        self.catalogService = catalogService
        self.ledgerService = ledgerService
        self.catalog = []
        self.redemptions = []
        self.isLoading = true
        self.isPreviewMode = false
        self.currentHouseholdId = householdStore.householdId
        observeHouseholds(store: householdStore)
        attachCatalogListener(for: householdStore.householdId)
        attachLedgerListener(for: householdStore.householdId)
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
        catalogListener?.cancel()
        ledgerListener?.cancel()
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
    
    private func switchHousehold(to newId: String) async {
        guard !isPreviewMode else { return }
        currentHouseholdId = newId
        attachCatalogListener(for: newId)
        attachLedgerListener(for: newId)
    }
    
    private func attachCatalogListener(for householdId: String) {
        catalogListener?.cancel()
        guard !isPreviewMode else { return }
        guard !householdId.isEmpty else {
            catalog = []
            isLoading = false
            return
        }
        catalogListener = catalogService.observeCatalog(for: householdId) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let items):
                    self.catalog = items.sorted { $0.cost < $1.cost }
                    self.isLoading = false
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func attachLedgerListener(for householdId: String) {
        ledgerListener?.cancel()
        guard !isPreviewMode else { return }
        guard !householdId.isEmpty else {
            redemptions = []
            return
        }
        ledgerListener = ledgerService.observeRedemptions(for: householdId) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let records):
                    self.redemptions = records.sorted { $0.redeemedAt > $1.redeemedAt }
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    @discardableResult
    func addReward(name: String, cost: Int) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, cost > 0 else { return false }
        let reward = RewardItem(name: trimmed, cost: cost)
        if isPreviewMode {
            catalog.append(reward)
            catalog.sort { $0.cost < $1.cost }
            return true
        }
        guard !currentHouseholdId.isEmpty else {
            error = String(localized: "rewards.error.missingHousehold")
            return false
        }
        do {
            try await catalogService.addReward(reward, to: currentHouseholdId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func deleteReward(_ reward: RewardItem) async -> Bool {
        if isPreviewMode {
            catalog.removeAll { $0.id == reward.id }
            return true
        }
        guard !currentHouseholdId.isEmpty else {
            error = String(localized: "rewards.error.missingHousehold")
            return false
        }
        do {
            try await catalogService.deleteReward(reward, from: currentHouseholdId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func redeem(_ reward: RewardItem, by member: HouseholdMember) async -> Bool {
        guard !isProcessing else { return false }
        let newRedemption = RewardRedemption(
            rewardId: reward.id,
            rewardName: reward.name,
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
        
        do {
            try await ledgerService.addRedemption(newRedemption, householdId: currentHouseholdId)
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
    
    func observeCatalog(for householdId: String, handler: @escaping (Result<[RewardItem], Error>) -> Void) -> ListenerToken {
        handler(.success(catalog))
        return BlockListenerToken {}
    }
    
    func addReward(_ reward: RewardItem, to householdId: String) async throws {}
    
    func deleteReward(_ reward: RewardItem, from householdId: String) async throws {}
}

final class UserDefaultsRewardCatalogService: RewardCatalogService {
    private let defaults: UserDefaults
    private let keyPrefix = "rewards.catalog."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var listeners: [String: [UUID: (Result<[RewardItem], Error>) -> Void]] = [:]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func observeCatalog(for householdId: String, handler: @escaping (Result<[RewardItem], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var group = listeners[householdId, default: [:]]
        group[id] = handler
        listeners[householdId] = group
        handler(.success(currentCatalog(for: householdId)))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func addReward(_ reward: RewardItem, to householdId: String) async throws {
        var catalog = currentCatalog(for: householdId)
        catalog.append(reward)
        try persist(catalog, householdId: householdId)
    }
    
    func deleteReward(_ reward: RewardItem, from householdId: String) async throws {
        var catalog = currentCatalog(for: householdId)
        catalog.removeAll { $0.id == reward.id }
        try persist(catalog, householdId: householdId)
    }
    
    private func currentCatalog(for householdId: String) -> [RewardItem] {
        guard let data = defaults.data(forKey: keyPrefix + householdId),
              let decoded = try? decoder.decode([RewardItem].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private func persist(_ catalog: [RewardItem], householdId: String) throws {
        let data = try encoder.encode(catalog)
        defaults.set(data, forKey: keyPrefix + householdId)
        notifyCatalogListeners(for: householdId, with: catalog)
    }
    
    private func notifyCatalogListeners(for householdId: String, with catalog: [RewardItem]) {
        listeners[householdId]?.values.forEach { $0(.success(catalog)) }
    }
}

final class UserDefaultsRewardLedgerService: RewardLedgerService {
    private let defaults: UserDefaults
    private let keyPrefix = "rewards.ledger."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var listeners: [String: [UUID: (Result<[RewardRedemption], Error>) -> Void]] = [:]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func observeRedemptions(for householdId: String, handler: @escaping (Result<[RewardRedemption], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var group = listeners[householdId, default: [:]]
        group[id] = handler
        listeners[householdId] = group
        handler(.success(currentLedger(for: householdId)))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func addRedemption(_ redemption: RewardRedemption, householdId: String) async throws {
        var ledger = currentLedger(for: householdId)
        ledger.insert(redemption, at: 0)
        try persist(ledger, householdId: householdId)
    }
    
    private func currentLedger(for householdId: String) -> [RewardRedemption] {
        guard let data = defaults.data(forKey: keyPrefix + householdId),
              let decoded = try? decoder.decode([RewardRedemption].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private func persist(_ ledger: [RewardRedemption], householdId: String) throws {
        let data = try encoder.encode(ledger)
        defaults.set(data, forKey: keyPrefix + householdId)
        notifyLedgerListeners(for: householdId, with: ledger)
    }
    
    private func notifyLedgerListeners(for householdId: String, with ledger: [RewardRedemption]) {
        listeners[householdId]?.values.forEach { $0(.success(ledger)) }
    }
}

final class InMemoryRewardLedgerService: RewardLedgerService {
    private var storage: [String: [RewardRedemption]] = [:]
    private var listeners: [String: [UUID: (Result<[RewardRedemption], Error>) -> Void]] = [:]
    
    func observeRedemptions(for householdId: String, handler: @escaping (Result<[RewardRedemption], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var group = listeners[householdId, default: [:]]
        group[id] = handler
        listeners[householdId] = group
        handler(.success(storage[householdId] ?? []))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func addRedemption(_ redemption: RewardRedemption, householdId: String) async throws {
        var ledger = storage[householdId] ?? []
        ledger.insert(redemption, at: 0)
        storage[householdId] = ledger
        listeners[householdId]?.values.forEach { $0(.success(ledger)) }
    }
}

final class InMemoryRewardCatalogService: RewardCatalogService {
    private var storage: [String: [RewardItem]]
    private var listeners: [String: [UUID: (Result<[RewardItem], Error>) -> Void]] = [:]
    
    init(initial: [String: [RewardItem]] = [:]) {
        self.storage = initial
    }
    
    func observeCatalog(for householdId: String, handler: @escaping (Result<[RewardItem], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var group = listeners[householdId, default: [:]]
        group[id] = handler
        listeners[householdId] = group
        handler(.success(storage[householdId] ?? []))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func addReward(_ reward: RewardItem, to householdId: String) async throws {
        var catalog = storage[householdId] ?? []
        catalog.append(reward)
        storage[householdId] = catalog
        listeners[householdId]?.values.forEach { $0(.success(catalog)) }
    }
    
    func deleteReward(_ reward: RewardItem, from householdId: String) async throws {
        var catalog = storage[householdId] ?? []
        catalog.removeAll { $0.id == reward.id }
        storage[householdId] = catalog
        listeners[householdId]?.values.forEach { $0(.success(catalog)) }
    }
}
