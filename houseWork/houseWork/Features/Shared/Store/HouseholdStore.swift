//
//  HouseholdStore.swift
//  houseWork
//
//  Tracks the current household metadata (ID + name) used across the app.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class HouseholdStore: ObservableObject {
    @Published var householdId: String
    @Published var householdName: String
    @Published private(set) var households: [HouseholdSummary] = []
    @Published var error: String?
    @Published var isLoading = true
    
    private let defaults = UserDefaults.standard
    private let idKey = "householdId"
    private let nameKey = "householdName"
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentUserId: String?
    
    init() {
        let savedId = defaults.string(forKey: idKey)
        let savedName = defaults.string(forKey: nameKey)
        self.householdId = savedId?.isEmpty == false ? savedId! : "demo-household"
        self.householdName = savedName?.isEmpty == false ? savedName! : "Demo Household"
    }
    
    deinit {
        listener?.remove()
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
    
    func addHousehold(name: String, id: String) async {
        guard let userId = currentUserId else {
            error = "Please sign in to create a household."
            return
        }
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedName.isEmpty else { return }
        do {
            try await db.collection("households").document(trimmedId).setData([
                "name": trimmedName,
                "ownerId": userId,
                "memberIds": FieldValue.arrayUnion([userId]),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func rename(household: HouseholdSummary, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await db.collection("households").document(household.id).updateData([
                "name": trimmed,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            if household.id == householdId {
                update(name: trimmed, id: householdId)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func delete(household: HouseholdSummary) async {
        guard household.id != householdId else {
            error = "Cannot delete the active household. Please switch first."
            return
        }
        do {
            try await db.collection("households").document(household.id).delete()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateUserContext(userId: String?) {
        guard userId != currentUserId else { return }
        listener?.remove()
        currentUserId = userId
        households = []
        isLoading = true
        guard let userId else {
            isLoading = false
            return
        }
        attachListener(for: userId)
    }
    
    private func attachListener(for userId: String) {
        listener = db.collection("households")
            .whereField("memberIds", arrayContains: userId)
            .order(by: "name", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.error = error.localizedDescription
                        self.isLoading = false
                        return
                    }
                    guard let documents = snapshot?.documents else {
                        self.households = []
                        self.isLoading = false
                        return
                    }
                    self.households = documents.compactMap { doc in
                        let name = doc.get("name") as? String ?? "Unnamed"
                        return HouseholdSummary(id: doc.documentID, name: name)
                    }
                    if !self.households.contains(where: { $0.id == self.householdId }),
                       let first = self.households.first {
                        self.select(first)
                    }
                    self.isLoading = false
                }
            }
    }
}

struct HouseholdSummary: Identifiable, Hashable {
    let id: String
    var name: String
}
