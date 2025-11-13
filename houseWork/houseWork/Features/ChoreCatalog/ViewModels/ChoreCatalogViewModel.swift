//
//  ChoreCatalogViewModel.swift
//  houseWork
//
//  Handles filtering, sorting, and CRUD operations for the chore template list.
//

import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class ChoreCatalogViewModel: ObservableObject {
    @Published private(set) var templates: [ChoreTemplate]
    @Published var searchText: String = ""
    @Published var selectedTag: String?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var mutationError: String?
    @Published private(set) var isMutating = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentHouseholdId: String?
    
    init(templates: [ChoreTemplate] = []) {
        self.templates = templates
    }
    
    deinit {
        listener?.remove()
    }
    
    var availableTags: [String] {
        let tags = templates.flatMap(\.tags)
        return Array(Set(tags)).sorted()
    }
    
    var filteredTemplates: [ChoreTemplate] {
        templates.filter { template in
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool
            if trimmed.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = template.title.localizedCaseInsensitiveContains(trimmed) ||
                template.details.localizedCaseInsensitiveContains(trimmed)
            }
            
            let matchesTag: Bool
            if let selectedTag {
                matchesTag = template.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
            } else {
                matchesTag = true
            }
            
            return matchesSearch && matchesTag
        }
    }
    
    func startListening(for householdId: String) {
        guard !householdId.isEmpty else { return }
        guard householdId != currentHouseholdId else { return }
        
        listener?.remove()
        currentHouseholdId = householdId
        isLoading = true
        templates = []
        error = nil
        
        listener = catalogCollection(for: householdId)
            .order(by: "title", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.error = error.localizedDescription
                        self.isLoading = false
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    self.templates = documents.compactMap { ChoreTemplate(document: $0) }
                    self.isLoading = false
                }
            }
    }
    
    func createTemplate(_ template: ChoreTemplate) async {
        await performMutation {
            let householdId = try requireHouseholdId()
            try await catalogCollection(for: householdId)
                .document(template.id.uuidString)
                .setData(template.firestoreCreatePayload)
        }
    }
    
    func updateTemplate(_ template: ChoreTemplate) async {
        await performMutation {
            let householdId = try requireHouseholdId()
            try await catalogCollection(for: householdId)
                .document(template.id.uuidString)
                .setData(template.firestoreUpdatePayload, merge: true)
        }
    }
    
    func deleteTemplate(_ template: ChoreTemplate) async {
        await performMutation {
            let householdId = try requireHouseholdId()
            try await catalogCollection(for: householdId)
                .document(template.id.uuidString)
                .delete()
        }
    }
    
    private func catalogCollection(for householdId: String) -> CollectionReference {
        db.collection("households")
            .document(householdId)
            .collection("choreTemplates")
    }
    
    private func requireHouseholdId() throws -> String {
        guard let currentHouseholdId else {
            throw CatalogError.missingHousehold
        }
        return currentHouseholdId
    }
    
    private func performMutation(_ work: () async throws -> Void) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await work()
            mutationError = nil
        } catch {
            mutationError = error.localizedDescription
        }
    }
}

extension ChoreCatalogViewModel {
    enum CatalogError: LocalizedError {
        case missingHousehold
        
        var errorDescription: String? {
            switch self {
            case .missingHousehold:
                return "Missing household context. Select a household and try again."
            }
        }
    }
}
