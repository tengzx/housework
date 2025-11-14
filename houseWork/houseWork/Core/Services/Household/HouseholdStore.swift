//
//  HouseholdStore.swift
//  houseWork
//
//  Tracks the current household metadata (ID + name) used across the app.
//

import Foundation
import Combine

@MainActor
final class HouseholdStore: ObservableObject {
    @Published var householdId: String
    @Published var householdName: String
    @Published private(set) var households: [HouseholdSummary] = []
    @Published var error: String?
    @Published var isLoading = true
    
    private let defaults: UserDefaults
    private let idKey = "householdId"
    private let nameKey = "householdName"
    private let service: HouseholdService
    private var listener: ListenerToken?
    private var currentUserId: String?
    
    init(
        service: HouseholdService = FirestoreHouseholdService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        let savedId = defaults.string(forKey: idKey)
        let savedName = defaults.string(forKey: nameKey)
        self.householdId = savedId?.isEmpty == false ? savedId! : "demo-household"
        self.householdName = savedName?.isEmpty == false ? savedName! : "Demo Household"
    }
    
    deinit {
        listener?.cancel()
    }
    
    func update(name: String, id: String) {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        householdId = trimmedId
        householdName = trimmedName.isEmpty ? "Household" : trimmedName
        defaults.set(householdId, forKey: idKey)
        defaults.set(householdName, forKey: nameKey)
    }
    
    func select(_ summary: HouseholdSummary) {
        update(name: summary.name, id: summary.id)
    }
    
    @discardableResult
    func createHousehold(named name: String) async -> Bool {
        guard let userId = currentUserId else {
            error = "Please sign in to create a household."
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        do {
            let summary = try await service.createHousehold(named: trimmedName, ownerId: userId)
            households = [summary] + households.filter { $0.id != summary.id }
            select(summary)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    func rename(household: HouseholdSummary, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await service.renameHousehold(id: household.id, to: trimmed)
            if household.id == householdId {
                update(name: trimmed, id: householdId)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func delete(household: HouseholdSummary) async {
        let deletingActive = household.id == householdId
        if deletingActive {
            if let alternative = households.first(where: { $0.id != household.id }) {
                select(alternative)
            } else {
                clearSelection()
            }
        }
        do {
            try await service.deleteHousehold(id: household.id)
            households.removeAll { $0.id == household.id }
            if deletingActive, households.isEmpty {
                clearSelection()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateUserContext(userId: String?, force: Bool = false) {
        if !force, userId == currentUserId { return }
        listener?.cancel()
        currentUserId = userId
        households = []
        clearSelection()
        isLoading = true
        guard let userId else {
            isLoading = false
            return
        }
        attachListener(for: userId)
    }
    
    func refreshInviteCode(for household: HouseholdSummary) async -> String? {
        guard let userId = currentUserId else {
            error = "Please sign in."
            return nil
        }
        guard households.contains(where: { $0.id == household.id }) else {
            error = "Household not found."
            return nil
        }
        do {
            let code = try await service.refreshInviteCode(for: household.id)
            error = nil
            return code
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
    
    @discardableResult
    func joinHousehold(using inviteCode: String) async -> Bool {
        guard let userId = currentUserId else {
            error = "Please sign in."
            return false
        }
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }
        do {
            let summary = try await service.joinHousehold(inviteCode: trimmed, userId: userId)
            households = [summary] + households.filter { $0.id != summary.id }
            select(summary)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    private func attachListener(for userId: String) {
        listener = service.observeHouseholds(for: userId) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let summaries):
                    self.households = summaries
                    if let active = summaries.first(where: { $0.id == self.householdId }) {
                        self.select(active)
                    } else if let first = summaries.first {
                        self.select(first)
                    } else {
                        self.clearSelection()
                    }
                    self.isLoading = false
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func clearSelection() {
        householdId = ""
        householdName = "No Household"
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: nameKey)
    }
}

struct HouseholdSummary: Identifiable, Hashable {
    let id: String
    var name: String
    var inviteCode: String?
}
