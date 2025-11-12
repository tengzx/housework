//
//  TagStore.swift
//  houseWork
//
//  Centralized registry of household tags that can be extended from Settings.
//

import Foundation
import Combine
import SwiftUI

struct TagItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

final class TagStore: ObservableObject {
    @Published private(set) var tags: [TagItem]
    
    init(initialTags: [String] = ["Kitchen", "Laundry", "Cleaning", "Errands", "Yard"]) {
        self.tags = initialTags
            .map { TagItem(name: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func addTag(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        withAnimation {
            tags.append(TagItem(name: trimmed))
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    func rename(tag: TagItem, to newName: String) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            tags[index].name = trimmed
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    func delete(at offsets: IndexSet) {
        withAnimation {
            tags.remove(atOffsets: offsets)
        }
    }
}
