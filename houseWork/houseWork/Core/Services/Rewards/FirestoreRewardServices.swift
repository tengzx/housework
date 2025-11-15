//
//  FirestoreRewardServices.swift
//  houseWork
//
//  Persists reward catalog and redemption history in Firestore.
//

import Foundation
import FirebaseFirestore

final class FirestoreRewardCatalogService: RewardCatalogService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func observeCatalog(for householdId: String, handler: @escaping (Result<[RewardItem], Error>) -> Void) -> ListenerToken {
        let registration = collection(for: householdId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    handler(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    handler(.success([]))
                    return
                }
                let items: [RewardItem] = documents.compactMap { document in
                    let data = document.data()
                    guard let name = data["name"] as? String,
                          let cost = data["cost"] as? Int else { return nil }
                    let id = UUID(uuidString: document.documentID) ?? UUID()
                    return RewardItem(id: id, name: name, cost: cost)
                }
                handler(.success(items))
            }
        return FirestoreListenerToken(registration: registration)
    }
    
    func addReward(_ reward: RewardItem, to householdId: String) async throws {
        try await collection(for: householdId)
            .document(reward.id.uuidString)
            .setData([
                "name": reward.name,
                "cost": reward.cost,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
    }
    
    func deleteReward(_ reward: RewardItem, from householdId: String) async throws {
        try await collection(for: householdId)
            .document(reward.id.uuidString)
            .delete()
    }
    
    private func collection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("rewardsCatalog")
    }
}

final class FirestoreRewardLedgerService: RewardLedgerService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func observeRedemptions(for householdId: String, handler: @escaping (Result<[RewardRedemption], Error>) -> Void) -> ListenerToken {
        let registration = collection(for: householdId)
            .order(by: "redeemedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    handler(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    handler(.success([]))
                    return
                }
                let records: [RewardRedemption] = documents.compactMap { document in
                    let data = document.data()
                    guard let rewardIdString = data["rewardId"] as? String,
                          let memberIdString = data["memberId"] as? String,
                          let memberName = data["memberName"] as? String,
                          let rewardName = data["rewardName"] as? String,
                          let cost = data["cost"] as? Int,
                          let rewardId = UUID(uuidString: rewardIdString),
                          let memberId = UUID(uuidString: memberIdString) else {
                        return nil
                    }
                    let timestamp = data["redeemedAt"] as? Timestamp
                    let date = timestamp?.dateValue() ?? Date()
                    let id = UUID(uuidString: document.documentID) ?? UUID()
                    return RewardRedemption(
                        id: id,
                        rewardId: rewardId,
                        rewardName: rewardName,
                        memberId: memberId,
                        memberName: memberName,
                        redeemedAt: date,
                        cost: cost
                    )
                }
                handler(.success(records))
            }
        return FirestoreListenerToken(registration: registration)
    }
    
    func addRedemption(_ redemption: RewardRedemption, householdId: String) async throws {
        var payload: [String: Any] = [
            "rewardId": redemption.rewardId.uuidString,
            "rewardName": redemption.rewardName,
            "memberId": redemption.memberId.uuidString,
            "memberName": redemption.memberName,
            "cost": redemption.cost,
            "redeemedAt": FieldValue.serverTimestamp()
        ]
        if let createdAt = redemption.redeemedAt as Date? {
            payload["localRedeemedAt"] = Timestamp(date: createdAt)
        }
        try await collection(for: householdId)
            .document(redemption.id.uuidString)
            .setData(payload, merge: true)
    }
    
    private func collection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("rewardRedemptions")
    }
}
