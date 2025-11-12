//
//  TaskBoardStore.swift
//  houseWork
//
//  Shared store that owns the household task list and exposes helpers to mutate it.
//

import Foundation
import SwiftUI
import Combine

final class TaskBoardStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published var currentMember: HouseholdMember
    
    init(
        tasks: [TaskItem] = TaskItem.fixtures(),
        currentMember: HouseholdMember = HouseholdMember.samples.first ?? HouseholdMember(name: "You", accentColor: .blue)
    ) {
        self.tasks = tasks
        self.currentMember = currentMember
    }
    
    func enqueue(template: ChoreTemplate) {
        let newTask = TaskItem(
            title: template.title,
            details: template.details,
            status: .backlog,
            dueDate: Date().addingTimeInterval(60 * 60 * 24),
            score: template.baseScore,
            roomTag: template.tags.first ?? "General",
            assignedMembers: [],
            originTemplateID: template.id
        )
        withAnimation {
            tasks.insert(newTask, at: 0)
        }
    }
    
    func startTask(_ task: TaskItem) {
        update(task) { item in
            var updated = item
            updated.status = .inProgress
            if updated.assignedMembers.isEmpty {
                updated.assignedMembers = [currentMember]
            }
            return updated
        }
    }
    
    func completeTask(_ task: TaskItem) {
        update(task) { item in
            var updated = item
            updated.status = .completed
            return updated
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
    
    private func update(_ task: TaskItem, transform: (TaskItem) -> TaskItem) {
        guard let idx = tasks.firstIndex(of: task) else { return }
        let newValue = transform(task)
        withAnimation {
            tasks[idx] = newValue
        }
    }
}
