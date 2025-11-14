//
//  ChoreTemplate.swift
//  houseWork
//
//  Defines the chore template model and supporting metadata used throughout
//  the Chore Catalog feature.
//

import Foundation

struct ChoreTemplate: Identifiable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var tags: [String]
    var frequency: ChoreFrequency
    var baseScore: Int
    var estimatedMinutes: Int
    
    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        tags: [String],
        frequency: ChoreFrequency,
        baseScore: Int,
        estimatedMinutes: Int
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.tags = tags
        self.frequency = frequency
        self.baseScore = baseScore
        self.estimatedMinutes = estimatedMinutes
    }
}

extension ChoreTemplate {
    static let samples: [ChoreTemplate] = [
        .init(
            title: "Kitchen Reset",
            details: "Load dishwasher, wipe counters, empty trash.",
            tags: ["Kitchen", "Daily"],
            frequency: .daily,
            baseScore: 15,
            estimatedMinutes: 20
        ),
        .init(
            title: "Laundry Cycle",
            details: "Wash, dry, and fold one load of laundry.",
            tags: ["Laundry", "Weekly"],
            frequency: .weekly,
            baseScore: 20,
            estimatedMinutes: 45
        ),
        .init(
            title: "Vacuum Common Areas",
            details: "Living room, hallway, and entry rug.",
            tags: ["Cleaning"],
            frequency: .weekly,
            baseScore: 25,
            estimatedMinutes: 30
        ),
        .init(
            title: "Grocery Run",
            details: "Stock pantry staples and produce.",
            tags: ["Errands"],
            frequency: .biweekly,
            baseScore: 30,
            estimatedMinutes: 60
        )
    ]
}

enum ChoreFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case biweekly
    case monthly
    case custom
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biweekly: "Bi-weekly"
        case .monthly: "Monthly"
        case .custom: "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .daily: "sun.max"
        case .weekly: "calendar"
        case .biweekly: "calendar.badge.plus"
        case .monthly: "calendar.circle"
        case .custom: "rectangle.and.pencil.and.ellipsis"
        }
    }
}
