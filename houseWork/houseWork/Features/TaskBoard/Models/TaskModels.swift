//
//  TaskModels.swift
//  houseWork
//
//  Domain models powering the Task Board feature.
//

import Foundation
import SwiftUI

enum TaskStatus: String, CaseIterable, Identifiable {
    case backlog
    case inProgress
    case completed
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .backlog: "Backlog"
        case .inProgress: "In Progress"
        case .completed: "Done"
        }
    }
    
    var iconName: String {
        switch self {
        case .backlog: "tray"
        case .inProgress: "clock"
        case .completed: "checkmark.circle"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .backlog: Color.orange.opacity(0.8)
        case .inProgress: Color.blue.opacity(0.8)
        case .completed: Color.green.opacity(0.9)
        }
    }
}

enum TaskBoardFilter: String, CaseIterable, Identifiable {
    case all
    case mine
    case unassigned
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .all: "All"
        case .mine: "My Tasks"
        case .unassigned: "Unassigned"
        }
    }
}

struct TaskItem: Identifiable, Hashable {
    var id: UUID
    var title: String
    var details: String
    var status: TaskStatus
    var dueDate: Date
    var score: Int
    var roomTag: String
    var assignedMembers: [HouseholdMember]
    var originTemplateID: UUID?
    
    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        status: TaskStatus,
        dueDate: Date,
        score: Int,
        roomTag: String,
        assignedMembers: [HouseholdMember],
        originTemplateID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.dueDate = dueDate
        self.score = score
        self.roomTag = roomTag
        self.assignedMembers = assignedMembers
        self.originTemplateID = originTemplateID
    }
}

struct TaskSection: Identifiable {
    let id = UUID()
    var status: TaskStatus
    var tasks: [TaskItem]
}

extension TaskItem {
    static func fixtures(members: [HouseholdMember] = HouseholdMember.samples) -> [TaskItem] {
        [
            TaskItem(
                title: "Kitchen reset",
                details: "Unload dishwasher, wipe counters, restock soap.",
                status: .backlog,
                dueDate: .now.addingTimeInterval(60 * 60 * 4),
                score: 15,
                roomTag: "Kitchen",
                assignedMembers: [members[0]]
            ),
            TaskItem(
                title: "Laundry cycle",
                details: "Wash darks and fold when dry.",
                status: .inProgress,
                dueDate: .now.addingTimeInterval(60 * 60 * 8),
                score: 20,
                roomTag: "Laundry",
                assignedMembers: [members[1], members[2]]
            ),
            TaskItem(
                title: "Living room vacuum",
                details: "Vacuum rug, sofa cushions, and under coffee table.",
                status: .backlog,
                dueDate: .now.addingTimeInterval(60 * 60 * 24),
                score: 18,
                roomTag: "Living Room",
                assignedMembers: []
            ),
            TaskItem(
                title: "Bathroom deep clean",
                details: "Scrub shower tiles, sink, and mop floor.",
                status: .inProgress,
                dueDate: .now.addingTimeInterval(60 * 60 * 30),
                score: 30,
                roomTag: "Bathroom",
                assignedMembers: [members[3]]
            ),
            TaskItem(
                title: "Grocery run",
                details: "Restock pantry staples and fresh produce.",
                status: .completed,
                dueDate: .now.addingTimeInterval(-60 * 60 * 5),
                score: 25,
                roomTag: "Errands",
                assignedMembers: [members[1]]
            )
        ]
    }
}
