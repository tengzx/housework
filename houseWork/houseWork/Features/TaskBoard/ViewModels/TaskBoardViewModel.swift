//
//  TaskBoardViewModel.swift
//  houseWork
//
//  Controls filtering and state transitions for the Task Board.
//

import Foundation
import SwiftUI
import Combine

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

final class TaskBoardViewModel: ObservableObject {
    @Published var tasks: [TaskItem]
    @Published var selectedFilter: TaskBoardFilter = .all
    @Published var currentMember: HouseholdMember
    
    init(tasks: [TaskItem] = TaskItem.fixtures(), currentMember: HouseholdMember = TaskItem.sampleMembers[0]) {
        self.tasks = tasks
        self.currentMember = currentMember
    }
    
    var sections: [TaskSection] {
        TaskStatus.allCases.map { status in
            TaskSection(
                status: status,
                tasks: filteredTasks(for: status)
            )
        }.filter { !$0.tasks.isEmpty }
    }
    
    private func filteredTasks(for status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status }
            .filter(filterPredicate)
            .sorted { $0.dueDate < $1.dueDate }
    }
    
    private func filterPredicate(_ task: TaskItem) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .mine:
            return task.assignedMembers.contains(currentMember)
        case .unassigned:
            return task.assignedMembers.isEmpty
        }
    }
    
    var completionRate: Double {
        let total = Double(tasks.count)
        guard total > 0 else { return 0 }
        let done = Double(tasks.filter { $0.status == .completed }.count)
        return done / total
    }
    
    var overdueCount: Int {
        tasks.filter { $0.status != .completed && $0.dueDate < Date() }.count
    }
    
    func startTask(_ task: TaskItem) {
        updateTask(task) { item in
            var updated = item
            updated.status = .inProgress
            if updated.assignedMembers.isEmpty {
                updated.assignedMembers = [currentMember]
            }
            return updated
        }
    }
    
    func completeTask(_ task: TaskItem) {
        updateTask(task) { item in
            var updated = item
            updated.status = .completed
            return updated
        }
    }
    
    private func updateTask(_ task: TaskItem, transformer: (TaskItem) -> TaskItem) {
        guard let idx = tasks.firstIndex(of: task) else { return }
        let newValue = transformer(task)
        withAnimation {
            tasks[idx] = newValue
        }
    }
}
