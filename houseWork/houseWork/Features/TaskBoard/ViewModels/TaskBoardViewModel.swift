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
    @Published private(set) var calendarStartDate: Date
    @Published var selectedDate: Date {
        didSet { recalculateSections() }
    }
    
    let taskStore: TaskBoardStore
    let authStore: AuthStore
    let householdStore: HouseholdStore
    let tagStore: TagStore
    let memberDirectory: MemberDirectory
    let statusSegments: [StatusSegment] = StatusSegment.makeDefault()
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        taskStore: TaskBoardStore,
        authStore: AuthStore,
        householdStore: HouseholdStore,
        tagStore: TagStore,
        memberDirectory: MemberDirectory
    ) {
        let today = Date()
        self.taskStore = taskStore
        self.authStore = authStore
        self.householdStore = householdStore
        self.tagStore = tagStore
        self.memberDirectory = memberDirectory
        self.selectedDate = today
        self.calendarStartDate = Calendar.current.startOfWeek(for: today) ?? today
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
    
    func selectDate(_ date: Date) {
        selectedDate = date
        if !calendarDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
            calendarStartDate = Calendar.current.startOfWeek(for: date) ?? calendarStartDate
        }
    }
    
    func isSelected(date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    func showPreviousWeek() {
        guard let newStart = Calendar.current.date(byAdding: .day, value: -7, to: calendarStartDate) else { return }
        calendarStartDate = newStart
        selectedDate = newStart
    }
    
    func showNextWeek() {
        guard let newStart = Calendar.current.date(byAdding: .day, value: 7, to: calendarStartDate) else { return }
        calendarStartDate = newStart
        selectedDate = newStart
    }
    
    private func bind() {
        taskStore.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateSections()
            }
            .store(in: &cancellables)
        
        authStore.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateSections()
            }
            .store(in: &cancellables)
        
        taskStore.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        memberDirectory.$membersById
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateSections()
            }
            .store(in: &cancellables)
        
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
        let normalized = normalizedTasks(taskStore.tasks)
        let filtered = normalized.filter { filterPredicate($0) && isTask($0, on: selectedDate) }
        filteredTasks = filtered
        if let status = selectedStatus {
            sections = [TaskSection(status: status, tasks: orderedTasks(for: status, within: filtered))]
        } else {
            sections = TaskStatus.allCases.map { status in
                TaskSection(status: status, tasks: orderedTasks(for: status, within: filtered))
            }
        }
    }
    
    private func normalizedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        let enriched = memberDirectory.replaceMembers(in: tasks)
        guard let currentUser = authStore.currentUser else { return enriched }
        return enriched.map { $0.replacingMember(with: currentUser) }
    }
    
    private func orderedTasks(for status: TaskStatus, within tasks: [TaskItem]) -> [TaskItem] {
        return tasks
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                lhs.dueDate > rhs.dueDate
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
    
    private func isTask(_ task: TaskItem, on date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        return task.dueDate >= startOfDay && task.dueDate < endOfDay
    }
    
    var calendarDates: [Date] {
        let calendar = Calendar.current
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendarStartDate) }
    }
}

struct StatusSegment: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let icon: String
    let background: Color
    let status: TaskStatus?
}

private extension StatusSegment {
    static func makeDefault() -> [StatusSegment] {
        var items: [StatusSegment] = [
            StatusSegment(
                id: "all",
                title: LocalizedStringKey("taskBoard.filter.all"),
                icon: "rectangle.grid.2x2",
                background: Color(hex: "D6D8FF") ?? Color(.systemBlue).opacity(0.3),
                status: nil
            )
        ]
        items += TaskStatus.allCases.map { status in
            StatusSegment(
                id: status.rawValue,
                title: status.labelKey,
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

private extension Calendar {
    func startOfWeek(for date: Date) -> Date? {
        var components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = firstWeekday
        return self.date(from: components)
    }
}
