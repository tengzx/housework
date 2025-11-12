//
//  TaskBoardView.swift
//  houseWork
//
//  Displays the current household workload grouped by status.
//

import SwiftUI

struct TaskBoardView: View {
    @StateObject private var viewModel = TaskBoardViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    filterPicker
                    summaryRow
                    ForEach(viewModel.sections) { section in
                        TaskSectionView(
                            section: section,
                            startHandler: { viewModel.startTask($0) },
                            completeHandler: { viewModel.completeTask($0) }
                        )
                    }
                }
                .padding()
            }
            .background(Color(white: 0.95))
            .navigationTitle("Task Board")
        }
    }
    
    private var filterPicker: some View {
        Picker("Filter", selection: $viewModel.selectedFilter) {
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
                value: "\(Int(viewModel.completionRate * 100))%",
                subtitle: "of tasks done",
                icon: "checkmark.seal.fill",
                tint: .green
            )
            SummaryCard(
                title: "Overdue",
                value: "\(viewModel.overdueCount)",
                subtitle: "need attention",
                icon: "exclamationmark.triangle.fill",
                tint: viewModel.overdueCount > 0 ? .orange : .secondary
            )
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
}
