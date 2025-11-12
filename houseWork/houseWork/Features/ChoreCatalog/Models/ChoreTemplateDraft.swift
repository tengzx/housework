//
//  ChoreTemplateDraft.swift
//  houseWork
//
//  Temporary data structure backing the creation form before a template
//  is persisted.
//

import Foundation

struct ChoreTemplateDraft {
    var title: String = ""
    var details: String = ""
    var tagsText: String = ""
    var frequency: ChoreFrequency = .weekly
    var baseScore: Int = 20
    var estimatedMinutes: Int = 30
    
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
        
        return ChoreTemplate(
            title: trimmedTitle,
            details: trimmedDetails.isEmpty ? "No description yet." : trimmedDetails,
            tags: tags.isEmpty ? ["General"] : tags,
            frequency: frequency,
            baseScore: baseScore,
            estimatedMinutes: estimatedMinutes
        )
    }
}
