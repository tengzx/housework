//
//  TaskBoardViewModel.swift
//  houseWork
//
//  Coordinates Task Board filtering and mutations away from the view layer.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class TaskBoardViewModel: ObservableObject {
    @Published var selectedFilter: TaskBoardFilter = .all {
        didSet { recalculateSections() }
    }
    @Published var selectedStatus: TaskStatus? {
        didSet { recalculateSections() }
    }
    @Published var showingTaskComposer = false
    @Published var inspectingTask: TaskItem?
    @Published var editingTask: TaskItem?
    @Published var alertMessage: String?
    @Published private(set) var sections: [TaskSection] = []
    @Published private(set) var filteredTasks: [TaskItem] = []
    @Published private(set) var isLoading: Bool = true
    
    let taskStore: TaskBoardStore
    let authStore: AuthStore
    let householdStore: HouseholdStore
    let tagStore: TagStore
    let statusSegments: [StatusSegment] = StatusSegment.makeDefault()
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        taskStore: TaskBoardStore,
        authStore: AuthStore,
        householdStore: HouseholdStore,
        tagStore: TagStore
    ) {
        self.taskStore = taskStore
        self.authStore = authStore
        self.householdStore = householdStore
        self.tagStore = tagStore
        bind()
        recalculateSections()
    }
    
    var visibleSections: [TaskSection] {
        guard selectedStatus == nil else { return sections }
        return sections.filter { !$0.tasks.isEmpty }
    }
    
    func taskCount(for status: TaskStatus?) -> Int {
        guard let status else { return filteredTasks.count }
        return filteredTasks.filter { $0.status == status }.count
    }
    
    func canMutate(task: TaskItem) -> Bool {
        guard let currentUser = authStore.currentUser else { return false }
        return task.assignedMembers.contains(where: { $0.matches(currentUser) })
    }
    
    func refreshTasks() async {
        await taskStore.refresh()
    }
    
    func startTask(_ task: TaskItem) async {
        await taskStore.startTask(task, assignedTo: authStore.currentUser)
    }
    
    func completeTask(_ task: TaskItem) async {
        await taskStore.completeTask(task, actingUser: authStore.currentUser)
    }
    
    func quickComplete(_ task: TaskItem) async {
        await completeTask(task)
    }
    
    func deleteTask(_ task: TaskItem) async {
        await taskStore.deleteTask(task)
    }
    
    func presentComposer() {
        showingTaskComposer = true
    }
    
    private func bind() {
        taskStore.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateSections()
            }
            .store(in: &cancellables)
        
        taskStore.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        Publishers.Merge(taskStore.$error, taskStore.$mutationError)
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.alertMessage = message
            }
            .store(in: &cancellables)
    }
    
    private func recalculateSections() {
        let filtered = taskStore.tasks.filter { filterPredicate($0) }
        filteredTasks = filtered
        if let status = selectedStatus {
            sections = [TaskSection(status: status, tasks: orderedTasks(for: status, within: filtered))]
        } else {
            sections = TaskStatus.allCases.map { status in
                TaskSection(status: status, tasks: orderedTasks(for: status, within: filtered))
            }
        }
    }
    
    private func orderedTasks(for status: TaskStatus, within tasks: [TaskItem]) -> [TaskItem] {
        let currentUser = authStore.currentUser
        return tasks
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                let lhsMine = currentUser.map { user in lhs.assignedMembers.contains { $0.matches(user) } } ?? false
                let rhsMine = currentUser.map { user in rhs.assignedMembers.contains { $0.matches(user) } } ?? false
                if lhsMine != rhsMine {
                    return lhsMine && !rhsMine
                }
                return lhs.dueDate < rhs.dueDate
            }
    }
    
    private func filterPredicate(_ task: TaskItem) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .mine:
            guard let user = authStore.currentUser else { return false }
            return task.assignedMembers.contains(where: { $0.matches(user) })
        case .unassigned:
            return task.assignedMembers.isEmpty
        }
    }
}

struct StatusSegment: Identifiable {
    let id: String
    let title: String
    let icon: String
    let background: Color
    let status: TaskStatus?
}

private extension StatusSegment {
    static func makeDefault() -> [StatusSegment] {
        var items: [StatusSegment] = [
            StatusSegment(
                id: "all",
                title: "All",
                icon: "rectangle.grid.2x2",
                background: Color(hex: "D6D8FF") ?? Color(.systemBlue).opacity(0.3),
                status: nil
            )
        ]
        items += TaskStatus.allCases.map { status in
            StatusSegment(
                id: status.rawValue,
                title: status.label,
                icon: status.iconName,
                background: segmentBackground(for: status),
                status: status
            )
        }
        return items
    }
    
    private static func segmentBackground(for status: TaskStatus) -> Color {
        switch status {
        case .backlog:
            return Color(hex: "FFF4A9") ?? Color.yellow.opacity(0.3)
        case .inProgress:
            return Color(hex: "FAD2E7") ?? Color.pink.opacity(0.3)
        case .completed:
            return Color(hex: "D8F4F0") ?? Color.green.opacity(0.3)
        }
    }
}
