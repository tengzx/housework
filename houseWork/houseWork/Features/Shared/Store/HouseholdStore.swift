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
    
    @discardableResult
    func createHousehold(named name: String) async -> Bool {
        guard let userId = currentUserId else {
            error = "Please sign in to create a household."
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        let docRef = db.collection("households").document()
        do {
            let inviteCode = generateInviteCode()
            try await docRef.setData([
                "name": trimmedName,
                "ownerId": userId,
                "memberIds": [userId],
                "inviteCode": inviteCode,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            let summary = HouseholdSummary(id: docRef.documentID, name: trimmedName, inviteCode: inviteCode)
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
    
    func updateUserContext(userId: String?, force: Bool = false) {
        if !force, userId == currentUserId { return }
        listener?.remove()
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
        let newCode = generateInviteCode()
        do {
            try await db.collection("households").document(household.id).updateData([
                "inviteCode": newCode,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            error = nil
            return newCode
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
            let snapshot = try await db.collection("households")
                .whereField("inviteCode", isEqualTo: trimmed)
                .limit(to: 1)
                .getDocuments()
            guard let document = snapshot.documents.first else {
                error = "Invite code not found."
                return false
            }
            try await document.reference.updateData([
                "memberIds": FieldValue.arrayUnion([userId]),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            let name = document.get("name") as? String ?? "Household"
            let inviteCode = document.get("inviteCode") as? String
            let summary = HouseholdSummary(id: document.documentID, name: name, inviteCode: inviteCode)
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
                        self.clearSelection()
                        return
                    }
                    self.households = documents.compactMap { doc in
                        let name = doc.get("name") as? String ?? "Unnamed"
                        let code = doc.get("inviteCode") as? String
                        return HouseholdSummary(id: doc.documentID, name: name, inviteCode: code)
                    }
                    if let active = self.households.first(where: { $0.id == self.householdId }) {
                        self.select(active)
                    } else if let first = self.households.first {
                        self.select(first)
                    } else {
                        self.clearSelection()
                    }
                    self.isLoading = false
                }
            }
    }
    
    private func clearSelection() {
        householdId = ""
        householdName = "No Household"
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: nameKey)
    }
    
    private func generateInviteCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        for _ in 0..<length {
            if let char = alphabet.randomElement() {
                result.append(char)
            }
        }
        return result
    }
}

struct HouseholdSummary: Identifiable, Hashable {
    let id: String
    var name: String
    var inviteCode: String?
}
