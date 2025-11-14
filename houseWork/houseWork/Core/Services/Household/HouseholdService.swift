//
//  HouseholdService.swift
//  houseWork
//
//  Abstract Firestore access for household operations.
//

import Foundation
import FirebaseFirestore

protocol HouseholdService {
    func observeHouseholds(for userId: String, handler: @escaping (Result<[HouseholdSummary], Error>) -> Void) -> ListenerToken
    func createHousehold(named name: String, ownerId: String) async throws -> HouseholdSummary
    func renameHousehold(id: String, to newName: String) async throws
    func deleteHousehold(id: String) async throws
    func refreshInviteCode(for id: String) async throws -> String
    func joinHousehold(inviteCode: String, userId: String) async throws -> HouseholdSummary
}

final class FirestoreHouseholdService: HouseholdService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func observeHouseholds(for userId: String, handler: @escaping (Result<[HouseholdSummary], Error>) -> Void) -> ListenerToken {
        let registration = db.collection("households")
            .whereField("memberIds", arrayContains: userId)
            .order(by: "name", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    handler(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    handler(.success([]))
                    return
                }
                let summaries = documents.compactMap { doc -> HouseholdSummary? in
                    let name = doc.get("name") as? String ?? "Unnamed"
                    let inviteCode = doc.get("inviteCode") as? String
                    return HouseholdSummary(id: doc.documentID, name: name, inviteCode: inviteCode)
                }
                handler(.success(summaries))
            }
        return FirestoreListenerToken(registration: registration)
    }
    
    func createHousehold(named name: String, ownerId: String) async throws -> HouseholdSummary {
        let docRef = db.collection("households").document()
        let inviteCode = generateInviteCode()
        try await docRef.setData([
            "name": name,
            "ownerId": ownerId,
            "memberIds": [ownerId],
            "inviteCode": inviteCode,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        return HouseholdSummary(id: docRef.documentID, name: name, inviteCode: inviteCode)
    }
    
    func renameHousehold(id: String, to newName: String) async throws {
        try await db.collection("households").document(id).updateData([
            "name": newName,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    func deleteHousehold(id: String) async throws {
        try await db.collection("households").document(id).delete()
    }
    
    func refreshInviteCode(for id: String) async throws -> String {
        let inviteCode = generateInviteCode()
        try await db.collection("households").document(id).updateData([
            "inviteCode": inviteCode,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        return inviteCode
    }
    
    func joinHousehold(inviteCode: String, userId: String) async throws -> HouseholdSummary {
        let snapshot = try await db.collection("households")
            .whereField("inviteCode", isEqualTo: inviteCode)
            .limit(to: 1)
            .getDocuments()
        guard let document = snapshot.documents.first else {
            throw NSError(domain: "houseWork", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invite code not found."])
        }
        try await document.reference.updateData([
            "memberIds": FieldValue.arrayUnion([userId]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        let name = document.get("name") as? String ?? "Household"
        let invite = document.get("inviteCode") as? String
        return HouseholdSummary(id: document.documentID, name: name, inviteCode: invite)
    }
    
    private func generateInviteCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

final class InMemoryHouseholdService: HouseholdService {
    struct Membership {
        var households: [HouseholdSummary]
    }
    
    private var households: [String: HouseholdSummary] = [:]
    private var memberships: [String: Set<String>] = [:]
    private var listeners: [String: [UUID: (Result<[HouseholdSummary], Error>) -> Void]] = [:]
    
    init(seedHouseholds: [HouseholdSummary] = [], membership: [String: [String]] = [:]) {
        for summary in seedHouseholds {
            households[summary.id] = summary
        }
        membership.forEach { userId, householdIds in
            memberships[userId] = Set(householdIds)
        }
    }
    
    func observeHouseholds(for userId: String, handler: @escaping (Result<[HouseholdSummary], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var userListeners = listeners[userId, default: [:]]
        userListeners[id] = handler
        listeners[userId] = userListeners
        handler(.success(currentHouseholds(for: userId)))
        return BlockListenerToken { [weak self] in
            self?.listeners[userId]?.removeValue(forKey: id)
        }
    }
    
    func createHousehold(named name: String, ownerId: String) async throws -> HouseholdSummary {
        let id = UUID().uuidString
        let summary = HouseholdSummary(id: id, name: name, inviteCode: generateInviteCode())
        households[id] = summary
        add(member: ownerId, to: id)
        return summary
    }
    
    func renameHousehold(id: String, to newName: String) async throws {
        guard var summary = households[id] else { return }
        summary.name = newName
        households[id] = summary
        notifyAll()
    }
    
    func deleteHousehold(id: String) async throws {
        households.removeValue(forKey: id)
        for (userId, ids) in memberships {
            if ids.contains(id) {
                memberships[userId]?.remove(id)
                notify(userId: userId)
            }
        }
    }
    
    func refreshInviteCode(for id: String) async throws -> String {
        guard var summary = households[id] else { return "" }
        let code = generateInviteCode()
        summary.inviteCode = code
        households[id] = summary
        notifyAll()
        return code
    }
    
    func joinHousehold(inviteCode: String, userId: String) async throws -> HouseholdSummary {
        guard let summary = households.values.first(where: { $0.inviteCode == inviteCode }) else {
            throw NSError(domain: "houseWork", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invite code not found."])
        }
        add(member: userId, to: summary.id)
        return summary
    }
    
    private func add(member userId: String, to householdId: String) {
        var set = memberships[userId, default: []]
        set.insert(householdId)
        memberships[userId] = set
        notify(userId: userId)
    }
    
    private func currentHouseholds(for userId: String) -> [HouseholdSummary] {
        let ids = memberships[userId] ?? []
        return ids.compactMap { households[$0] }
    }
    
    private func notify(userId: String) {
        let summaries = currentHouseholds(for: userId)
        listeners[userId]?.values.forEach { $0(.success(summaries)) }
    }
    
    private func notifyAll() {
        for userId in listeners.keys {
            notify(userId: userId)
        }
    }
    
    private func generateInviteCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
