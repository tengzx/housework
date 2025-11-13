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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    householdHeader
                    filterPicker
                    summaryRow
                    boardContent
                }
                .padding()
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
        } else if taskStore.tasks.isEmpty {
            ContentUnavailableView(
                "No tasks yet",
                systemImage: "tray"
            )
            .frame(maxWidth: .infinity)
        } else {
            ForEach(sections) { section in
                TaskSectionView(
                    section: section,
                    startHandler: { task in
                        Task {
                            await taskStore.startTask(task, assignedTo: authStore.currentUser)
                        }
                    },
                    completeHandler: { task in
                        Task {
                            await taskStore.completeTask(task)
                        }
                    }
                )
            }
        }
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
                        tint: segment.tint,
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
        taskStore.tasks
            .filter { $0.status == status && filterPredicate($0) }
            .sorted { $0.dueDate < $1.dueDate }
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
                tint: .accentColor,
                status: nil
            )
        ]
        items += TaskStatus.allCases.map { status in
            StatusSegment(
                id: status.rawValue,
                title: status.label,
                subtitle: subtitle(for: status),
                icon: status.iconName,
                tint: status.accentColor,
                status: status
            )
        }
        return items
    }
}

private struct StatusSegment: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let status: TaskStatus?
}

private struct TaskSectionView: View {
    let section: TaskSection
    let startHandler: (TaskItem) -> Void
    let completeHandler: (TaskItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(section.status.label) · \(section.tasks.count)", systemImage: section.status.iconName)
                    .font(.headline)
                Spacer()
            }
            LazyVStack(spacing: 12) {
                ForEach(section.tasks) { task in
                    TaskCardView(
                        task: task,
                        primaryButton: primaryButton(for: task),
                        secondaryButton: secondaryButton(for: task)
                    )
                }
            }
        }
    }
    
    private func primaryButton(for task: TaskItem) -> TaskCardButton? {
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
}

private struct StatusSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(isSelected ? tint : .primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(isSelected ? tint.opacity(0.8) : .secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
#if canImport(UIKit)
                .fill(isSelected ? tint.opacity(0.2) : Color(UIColor.systemBackground))
#else
                .fill(isSelected ? tint.opacity(0.2) : Color.white)
#endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? tint : Color.primary.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
    }
}

#Preview {
    TaskBoardView()
        .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
        .environmentObject(AuthStore())
        .environmentObject(HouseholdStore())
}
