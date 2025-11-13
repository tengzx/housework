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
                ScrollView {
                    VStack(spacing: 16) {
                        householdHeader
                        filterPicker
                        summaryRow
                        boardContent
                    }
                    .padding()
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
    
    @ViewBuilder
    private var boardContent: some View {
        if taskStore.isLoading && taskStore.tasks.isEmpty {
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
        } else {
            let allTasks = taskStore.tasks.filter(filterPredicate)
            if allTasks.isEmpty {
                ContentUnavailableView(
                    "No tasks yet",
                    systemImage: "tray"
                )
                .frame(maxWidth: .infinity)
            } else {
                let visibleSections = (selectedStatus == nil)
                ? sections.filter { !$0.tasks.isEmpty }
                : sections
                
                if visibleSections.isEmpty {
                    ContentUnavailableView("No tasks match", systemImage: "tray")
                }
                
                ForEach(visibleSections) { section in
                    TaskSectionView(
                        section: section,
                        currentUser: authStore.currentUser,
                        startHandler: { task in
                            Task {
                                await taskStore.startTask(task, assignedTo: authStore.currentUser)
                            }
                        },
                        completeHandler: { task in
                            Task {
                                await taskStore.completeTask(task, actingUser: authStore.currentUser)
                            }
                        },
                        deleteHandler: { task in
                            Task {
                                await taskStore.deleteTask(task)
                            }
                        }
                    )
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(statusSegments) { segment in
                Button {
                    selectedStatus = segment.status
                } label: {
                    StatusSummaryCard(
                        title: segment.title,
                        value: "\(taskCount(for: segment.status))",
                        subtitle: segment.subtitle,
                        icon: segment.icon,
                        background: segment.background,
                        isSelected: segment.status == selectedStatus
                    )
                }
                .buttonStyle(.plain)
            }
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
            return task.assignedMembers.contains(where: { $0.id == user.id })
        case .unassigned:
            return task.assignedMembers.isEmpty
        }
    }

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        let userId = authStore.currentUser?.id
        return taskStore.tasks
            .filter { $0.status == status && filterPredicate($0) }
            .sorted { lhs, rhs in
                let lhsMine = userId.map { id in lhs.assignedMembers.contains { $0.id == id } } ?? false
                let rhsMine = userId.map { id in rhs.assignedMembers.contains { $0.id == id } } ?? false
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

    private func subtitle(for status: TaskStatus?) -> String {
        guard let status else { return "All tasks" }
        switch status {
        case .backlog: return "待开始"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        }
    }
    
    private var statusSegments: [StatusSegment] {
        var items: [StatusSegment] = [
            StatusSegment(
                id: "all",
                title: "All",
                subtitle: "All tasks",
                icon: "rectangle.grid.2x2",
                background: hexColor("D6D8FF", fallback: Color(.systemBlue).opacity(0.3)),
                status: nil
            )
        ]
        items += TaskStatus.allCases.map { status in
            StatusSegment(
                id: status.rawValue,
                title: status.label,
                subtitle: subtitle(for: status),
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
    let subtitle: String
    let icon: String
    let background: Color
    let status: TaskStatus?
}

private struct TaskSectionView: View {
    let section: TaskSection
    let currentUser: HouseholdMember?
    let startHandler: (TaskItem) -> Void
    let completeHandler: (TaskItem) -> Void
    let deleteHandler: (TaskItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVStack(spacing: 12) {
                ForEach(section.tasks) { task in
                    TaskCardView(
                        task: task,
                        primaryButton: primaryButton(for: task),
                        secondaryButton: secondaryButton(for: task),
                        isActionEnabled: canMutate(task: task)
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteHandler(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
    
    private func primaryButton(for task: TaskItem) -> TaskCardButton? {
        guard canMutate(task: task) else { return nil }
        switch task.status {
        case .backlog:
            return TaskCardButton(
                title: "Start",
                systemImage: "play.circle.fill",
                style: .borderedProminent
            ) { startHandler(task) }
        case .inProgress:
            return TaskCardButton(
                title: "Complete",
                systemImage: "checkmark.circle.fill",
                style: .borderedProminent
            ) { completeHandler(task) }
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
            ) { completeHandler(task) }
        case .inProgress:
            return nil
        case .completed:
            return nil
        }
    }
    
    private func canMutate(task: TaskItem) -> Bool {
        guard let currentUser else { return false }
        return task.assignedMembers.contains(where: { $0.id == currentUser.id })
    }
}

private struct StatusSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let background: Color?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.black)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.black)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background ?? Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.35) : .clear, lineWidth: 2)
        )
    }
}

#Preview {
    TaskBoardView()
        .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
        .environmentObject(AuthStore())
        .environmentObject(HouseholdStore())
}
