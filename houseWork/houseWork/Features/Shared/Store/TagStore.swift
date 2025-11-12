//
//  TagStore.swift
//  houseWork
//
//  Centralized registry of household tags that can be extended from Settings.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

struct TagItem: Identifiable, Hashable {
    let id: String
    var name: String
    var colorHex: String?
}

@MainActor
final class TagStore: ObservableObject {
    @Published private(set) var tags: [TagItem] = []
    @Published var isLoading = true
    @Published var error: String?
    
    private let householdId: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    init(householdId: String = "ImcHKHZEu59W1zT7S27H") {
        self.householdId = householdId
        attachListener()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func attachListener() {
        listener = db.collection("households")
            .document(householdId)
            .collection("tags")
            .order(by: "name", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.error = error.localizedDescription
                        self.isLoading = false
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    self.tags = documents.compactMap { doc in
                        guard let name = doc.get("name") as? String else { return nil }
                        let color = doc.get("color") as? String
                        return TagItem(id: doc.documentID, name: name, colorHex: color)
                    }
                    self.isLoading = false
                }
            }
    }
    
    func addTag(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await tagCollection.document().setData([
                "name": trimmed,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func rename(tag: TagItem, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await tagCollection.document(tag.id).updateData([
                "name": trimmed,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func delete(at offsets: IndexSet) {
        let items = offsets.compactMap { tags.indices.contains($0) ? tags[$0] : nil }
        Task {
            for tag in items {
                await delete(tag: tag)
            }
        }
    }
    
    func delete(tag: TagItem) async {
        do {
            try await tagCollection.document(tag.id).delete()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private var tagCollection: CollectionReference {
        db.collection("households").document(householdId).collection("tags")
    }
}
