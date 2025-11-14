//
//  TagStore.swift
//  houseWork
//
//  Syncs household tags with Firestore.
//

import Foundation
import SwiftUI
import Combine

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
    
    private let householdStore: HouseholdStore
    private let service: TagService
    private var householdCancellable: AnyCancellable?
    private var listener: ListenerToken?
    private var currentHouseholdId: String
    
    init(
        householdStore: HouseholdStore,
        service: TagService = FirestoreTagService()
    ) {
        self.householdStore = householdStore
        self.service = service
        self.currentHouseholdId = householdStore.householdId
        attachListener(to: currentHouseholdId)
        householdCancellable = householdStore.$householdId
            .removeDuplicates()
            .sink { [weak self] newId in
                guard let self else { return }
                Task { @MainActor in
                    await self.switchHousehold(to: newId)
                }
            }
    }
    
    deinit {
        listener?.cancel()
        householdCancellable?.cancel()
    }
    
    private func switchHousehold(to id: String) async {
        guard !id.isEmpty, id != currentHouseholdId else { return }
        listener?.cancel()
        currentHouseholdId = id
        tags = []
        isLoading = true
        attachListener(to: id)
    }
    
    private func attachListener(to householdId: String) {
        listener = service.observeTags(householdId: householdId) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let tags):
                    self.tags = tags
                    self.isLoading = false
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func addTag(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await service.addTag(named: trimmed, householdId: currentHouseholdId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func rename(tag: TagItem, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await service.renameTag(id: tag.id, householdId: currentHouseholdId, newName: trimmed)
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
            try await service.deleteTag(id: tag.id, householdId: currentHouseholdId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
