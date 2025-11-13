//
//  TaskBoardView.swift
//  houseWork
//
//  Displays the current household workload grouped by status.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct TaskBoardView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var selectedFilter: TaskBoardFilter = .all
    @State private var selectedStatus: TaskStatus?
    @State private var showingHouseholdSheet = false
    @State private var alertMessage: String?
    @State private var showingTaskComposer = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    headerSection
                    boardContent
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(white: 0.95))
                .refreshable {
                    await taskStore.refresh()
                }
                floatingAddButton
            }
            .background(Color(white: 0.95))
        }
        .onReceive(taskStore.$error.compactMap { $0 }) { alertMessage = $0 }
        .onReceive(taskStore.$mutationError.compactMap { $0 }) { alertMessage = $0 }
        .alert(
            "Task Board Error",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text(alertMessage ?? "")
            }
        )
        .sheet(isPresented: $showingTaskComposer) {
            TaskComposerView()
                .environmentObject(taskStore)
                .environmentObject(authStore)
        }
    }
    
    private var headerSection: some View {
        Section {
            householdHeader
            filterPicker
            summaryRow
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    @ViewBuilder
    private var boardContent: some View {
        if taskStore.isLoading && taskStore.tasks.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Loading tasks…")
                        .padding(.vertical, 40)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            let allTasks = taskStore.tasks.filter(filterPredicate)
            if allTasks.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No tasks yet",
                        systemImage: "tray"
                    )
                    .frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                let visibleSections = (selectedStatus == nil)
                ? sections.filter { !$0.tasks.isEmpty }
                : sections
                
                if visibleSections.isEmpty {
                    Section {
                        ContentUnavailableView("No tasks match", systemImage: "tray")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                
                ForEach(visibleSections) { section in
                    taskSectionView(for: section)
                }
            }
        }
    }
    
    private var floatingAddButton: some View {
        Button {
            showingTaskComposer = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("Add Task")
    }
    
    private var householdHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(householdStore.households) { summary in
                    Button {
                        householdStore.select(summary)
                    } label: {
                        HStack {
                            Text(summary.name)
                            if summary.id == householdStore.householdId {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(householdStore.householdName)
                            .font(.title2.bold())
                        Text("ID: \(householdStore.householdId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var filterPicker: some View {
        Picker("Filter", selection: $selectedFilter) {
            ForEach(TaskBoardFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var summaryRow: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 160), spacing: 12), count: 2)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(statusSegments) { segment in
                Button {
                    selectedStatus = segment.status
                } label: {
                    StatusSummaryCard(
                        title: segment.title,
                        value: "\(taskCount(for: segment.status))",
                        icon: segment.icon,
                        background: segment.background,
                        isSelected: segment.status == selectedStatus
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private func taskSectionView(for section: TaskSection) -> some View {
        Section {
            ForEach(section.tasks) { task in
                TaskCardView(
                    task: task,
                    primaryButton: primaryButton(for: task),
                    secondaryButton: secondaryButton(for: task),
                    isActionEnabled: canMutate(task: task)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await taskStore.deleteTask(task)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 2)
            }
        } header: {
            Text(section.status.label)
                .font(.headline)
                .textCase(.none)
        }
    }

    private var sections: [TaskSection] {
        if let status = selectedStatus {
            return [TaskSection(status: status, tasks: tasks(for: status))]
        } else {
            return TaskStatus.allCases.map { status in
                TaskSection(status: status, tasks: tasks(for: status))
            }
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

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        let currentUser = authStore.currentUser
        return taskStore.tasks
            .filter { $0.status == status && filterPredicate($0) }
            .sorted { lhs, rhs in
                let lhsMine = currentUser.map { user in lhs.assignedMembers.contains { $0.matches(user) } } ?? false
                let rhsMine = currentUser.map { user in rhs.assignedMembers.contains { $0.matches(user) } } ?? false
                if lhsMine != rhsMine {
                    return lhsMine && !rhsMine
                }
                return lhs.dueDate < rhs.dueDate
            }
    }

    private func taskCount(for status: TaskStatus?) -> Int {
        if let status {
            return tasks(for: status).count
        }
        return taskStore.tasks
            .filter(filterPredicate)
            .count
    }

    private func primaryButton(for task: TaskItem) -> TaskCardButton? {
        guard canMutate(task: task) else { return nil }
        switch task.status {
        case .backlog:
            return TaskCardButton(
                title: "Start",
                systemImage: "play.circle.fill",
                style: .borderedProminent
            ) {
                Task {
                    await taskStore.startTask(task, assignedTo: authStore.currentUser)
                }
            }
        case .inProgress:
            return TaskCardButton(
                title: "Complete",
                systemImage: "checkmark.circle.fill",
                style: .borderedProminent
            ) {
                Task {
                    await taskStore.completeTask(task, actingUser: authStore.currentUser)
                }
            }
        case .completed:
            return nil
        }
    }
    
    private func secondaryButton(for task: TaskItem) -> TaskCardButton? {
        guard canMutate(task: task) else { return nil }
        switch task.status {
        case .backlog:
            return TaskCardButton(
                title: "Quick Done",
                systemImage: "checkmark.circle",
                style: .bordered
            ) {
                Task {
                    await taskStore.completeTask(task, actingUser: authStore.currentUser)
                }
            }
        case .inProgress, .completed:
            return nil
        }
    }
    
    private func canMutate(task: TaskItem) -> Bool {
        guard let currentUser = authStore.currentUser else { return false }
        return task.assignedMembers.contains(where: { $0.matches(currentUser) })
    }
    
    private var statusSegments: [StatusSegment] {
        var items: [StatusSegment] = [
            StatusSegment(
                id: "all",
                title: "All",
                icon: "rectangle.grid.2x2",
                background: hexColor("D6D8FF", fallback: Color(.systemBlue).opacity(0.3)),
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
    
    private func segmentBackground(for status: TaskStatus) -> Color {
        switch status {
        case .backlog:
            return hexColor("FFF4A9", fallback: Color.yellow.opacity(0.3))
        case .inProgress:
            return hexColor("FAD2E7", fallback: Color.pink.opacity(0.3))
        case .completed:
            return hexColor("D8F4F0", fallback: Color.green.opacity(0.3))
        }
    }
    
    private func hexColor(_ hex: String, fallback: Color) -> Color {
        Color(hex: hex) ?? fallback
    }
}

private struct StatusSegment: Identifiable {
    let id: String
    let title: String
    let icon: String
    let background: Color
    let status: TaskStatus?
}

private struct StatusSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let background: Color?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.title.bold())
                .foregroundStyle(.black)
                .frame(alignment: .center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background ?? Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.2) : .clear, lineWidth: 2)
        )
    }
}

#Preview {
    TaskBoardView()
        .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
        .environmentObject(AuthStore())
        .environmentObject(HouseholdStore())
}
