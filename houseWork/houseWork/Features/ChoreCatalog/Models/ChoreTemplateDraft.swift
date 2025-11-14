//
//  ChoreTemplateDraft.swift
//  houseWork
//
//  Temporary data structure backing the creation form before a template
//  is persisted.
//

import Foundation
import SwiftUI

struct ChoreTemplateDraft {
    var templateID: UUID?
    var title: String = ""
    var details: String = ""
    var tagsText: String = ""
    var frequency: ChoreFrequency = .weekly
    var baseScore: Int = 20
    var estimatedMinutes: Int = 30
    
    init() {}
    
    init(template: ChoreTemplate) {
        templateID = template.id
        title = template.title
        details = template.details
        tagsText = template.tags.joined(separator: ", ")
        frequency = template.frequency
        baseScore = template.baseScore
        estimatedMinutes = template.estimatedMinutes
    }
    
    mutating func reset() {
        self = ChoreTemplateDraft()
    }
    
    func buildTemplate() -> ChoreTemplate? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let descriptionText = trimmedDetails.isEmpty ? String(localized: "catalog.description.placeholder") : trimmedDetails
        return ChoreTemplate(
            id: templateID ?? UUID(),
            title: trimmedTitle,
            details: descriptionText,
            tags: tags.isEmpty ? ["General"] : tags,
            frequency: frequency,
            baseScore: baseScore,
            estimatedMinutes: estimatedMinutes
        )
    }
}
