//
//  ChoreCatalogViewModel.swift
//  houseWork
//
//  Handles filtering, sorting, and CRUD operations for the chore template list.
//

import SwiftUI
import Combine

final class ChoreCatalogViewModel: ObservableObject {
    @Published var templates: [ChoreTemplate]
    @Published var searchText: String = ""
    @Published var selectedTag: String?
    
    init(templates: [ChoreTemplate] = ChoreTemplate.samples) {
        self.templates = templates
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
    
    func addTemplate(_ template: ChoreTemplate) {
        withAnimation {
            templates.insert(template, at: 0)
        }
    }
    
    func updateTemplate(_ template: ChoreTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        withAnimation {
            templates[index] = template
        }
    }
}
