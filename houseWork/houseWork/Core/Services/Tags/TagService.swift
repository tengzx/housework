//
//  TagService.swift
//  houseWork
//
//  Abstraction over Firestore tag operations.
//

import Foundation
import FirebaseFirestore

protocol TagService {
    func observeTags(householdId: String, handler: @escaping (Result<[TagItem], Error>) -> Void) -> ListenerToken
    func addTag(named name: String, householdId: String) async throws
    func renameTag(id: String, householdId: String, newName: String) async throws
    func deleteTag(id: String, householdId: String) async throws
}

final class FirestoreTagService: TagService {
    private let db: Firestore
    
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }
    
    func observeTags(householdId: String, handler: @escaping (Result<[TagItem], Error>) -> Void) -> ListenerToken {
        let registration = db.collection("households")
            .document(householdId)
            .collection("tags")
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
                let tags = documents.compactMap { doc -> TagItem? in
                    guard let name = doc.get("name") as? String else { return nil }
                    let color = doc.get("color") as? String
                    return TagItem(id: doc.documentID, name: name, colorHex: color)
                }
                handler(.success(tags))
            }
        return FirestoreListenerToken(registration: registration)
    }
    
    func addTag(named name: String, householdId: String) async throws {
        try await tagCollection(householdId: householdId).document().setData([
            "name": name,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func renameTag(id: String, householdId: String, newName: String) async throws {
        try await tagCollection(householdId: householdId).document(id).updateData([
            "name": newName,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    func deleteTag(id: String, householdId: String) async throws {
        try await tagCollection(householdId: householdId).document(id).delete()
    }
    
    private func tagCollection(householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("tags")
    }
}

final class InMemoryTagService: TagService {
    private var backing: [String: [TagItem]] = [:]
    private var listeners: [String: [UUID: (Result<[TagItem], Error>) -> Void]] = [:]
    
    func observeTags(householdId: String, handler: @escaping (Result<[TagItem], Error>) -> Void) -> ListenerToken {
        let id = UUID()
        var householdListeners = listeners[householdId, default: [:]]
        householdListeners[id] = handler
        listeners[householdId] = householdListeners
        handler(.success(backing[householdId] ?? []))
        return BlockListenerToken { [weak self] in
            self?.listeners[householdId]?.removeValue(forKey: id)
        }
    }
    
    func addTag(named name: String, householdId: String) async throws {
        var tags = backing[householdId, default: []]
        let tag = TagItem(id: UUID().uuidString, name: name, colorHex: nil)
        tags.append(tag)
        backing[householdId] = tags
        notify(householdId)
    }
    
    func renameTag(id: String, householdId: String, newName: String) async throws {
        guard var tags = backing[householdId], let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].name = newName
        backing[householdId] = tags
        notify(householdId)
    }
    
    func deleteTag(id: String, householdId: String) async throws {
        guard var tags = backing[householdId] else { return }
        tags.removeAll { $0.id == id }
        backing[householdId] = tags
        notify(householdId)
    }
    
    private func notify(_ householdId: String) {
        let tags = backing[householdId] ?? []
        listeners[householdId]?.values.forEach { $0(.success(tags)) }
    }
}
