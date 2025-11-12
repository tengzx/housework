//
//  TaskBoardView.swift
//  houseWork
//
//  Displays the current household workload grouped by status.
//

import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var taskStore: TaskBoardStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var selectedFilter: TaskBoardFilter = .all
    @State private var showingHouseholdSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    householdHeader
                    filterPicker
                    summaryRow
                    ForEach(sections) { section in
                        TaskSectionView(
                            section: section,
                            startHandler: { taskStore.startTask($0, assignedTo: authStore.currentUser) },
                            completeHandler: { taskStore.completeTask($0) }
                        )
                    }
                }
                .padding()
            }
            .background(Color(white: 0.95))
            .navigationTitle("Task Board")
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
        HStack(spacing: 12) {
            SummaryCard(
                title: "Completion",
                value: "\(Int(taskStore.completionRate * 100))%",
                subtitle: "of tasks done",
                icon: "checkmark.seal.fill",
                tint: .green
            )
            SummaryCard(
                title: "Overdue",
                value: "\(taskStore.overdueCount)",
                subtitle: "need attention",
                icon: "exclamationmark.triangle.fill",
                tint: taskStore.overdueCount > 0 ? .orange : .secondary
            )
        }
    }
    
    private var sections: [TaskSection] {
        TaskStatus.allCases.map { status in
            let tasks = taskStore.tasks
                .filter { $0.status == status && filterPredicate($0) }
                .sorted { $0.dueDate < $1.dueDate }
            return TaskSection(status: status, tasks: tasks)
        }
        .filter { !$0.tasks.isEmpty }
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

private struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    TaskBoardView()
        .environmentObject(TaskBoardStore())
        .environmentObject(AuthStore())
}
