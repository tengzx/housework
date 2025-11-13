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
    @EnvironmentObject private var tagStore: TagStore
    @State private var selectedFilter: TaskBoardFilter = .all
    @State private var selectedStatus: TaskStatus?
    @State private var showingHouseholdSheet = false
    @State private var alertMessage: String?
    @State private var showingTaskComposer = false
    @State private var inspectingTask: TaskItem?
    @State private var editingTask: TaskItem?
    
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
        .sheet(item: $inspectingTask) { task in
            TaskDetailView(task: task)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task)
                .environmentObject(taskStore)
                .environmentObject(tagStore)
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
                    isActionEnabled: canMutate(task: task),
                    showsDetails: false
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    inspectingTask = task
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        editingTask = task
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                    
                    Button(role: .destructive) {
                        Task {
                            await taskStore.deleteTask(task)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 2)
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

private struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusRow
                    detailRow(title: "Due Date", value: task.dueDate.formatted(date: .abbreviated, time: .shortened))
                    detailRow(title: "Room Tag", value: task.roomTag)
                    detailRow(title: "Score", value: "\(task.score)")
                    detailRow(title: "Estimated Minutes", value: "\(task.estimatedMinutes)")
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)
                        Text(task.details)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Assigned Members")
                            .font(.headline)
                        if task.assignedMembers.isEmpty {
                            Text("Unassigned")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(task.assignedMembers, id: \.id) { member in
                                HStack(spacing: 12) {
                                    Text(member.initials)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(member.accentColor, in: Circle())
                                    VStack(alignment: .leading) {
                                        Text(member.name)
                                            .font(.subheadline)
                                        Text(member.id.uuidString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding()
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private var statusRow: some View {
        HStack {
            Label(task.status.label, systemImage: task.status.iconName)
                .font(.headline)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(task.status.accentColor.opacity(0.2), in: Capsule())
            Spacer()
            Text(task.status == .completed ? "Finished" : "Active")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
        }
        .padding(.vertical, 4)
    }
}

private struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskBoardStore
    @EnvironmentObject private var tagStore: TagStore
    
    let task: TaskItem
    @State private var title: String
    @State private var details: String
    @State private var dueDate: Date
    @State private var score: Int
    @State private var roomTag: String
    @State private var estimatedMinutes: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _details = State(initialValue: task.details)
        _dueDate = State(initialValue: task.dueDate)
        _score = State(initialValue: task.score)
        _roomTag = State(initialValue: task.roomTag)
        _estimatedMinutes = State(initialValue: task.estimatedMinutes)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                
                Section("Scheduling") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    Stepper(value: $estimatedMinutes, in: 5...240, step: 5) {
                        HStack {
                            Text("Estimated Time")
                            Spacer()
                            Text("\(estimatedMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $score, in: 5...100, step: 5) {
                        HStack {
                            Text("Score")
                            Spacer()
                            Text("\(score)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Tags") {
                    Picker("Room / Tag", selection: $roomTag) {
                        Text("General").tag("General")
                        ForEach(tagStore.tags) { tag in
                            Text(tag.name).tag(tag.name)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTask)
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveTask() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = roomTag.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let success = await taskStore.updateTaskDetails(
                task,
                title: trimmedTitle,
                details: trimmedDetails.isEmpty ? "No details yet." : trimmedDetails,
                dueDate: dueDate,
                score: score,
                roomTag: trimmedTag.isEmpty ? "General" : trimmedTag,
                estimatedMinutes: estimatedMinutes
            )
            await MainActor.run {
                isSaving = false
                if success {
                    dismiss()
                } else {
                    errorMessage = taskStore.mutationError ?? "Failed to save task."
                }
            }
        }
    }
}

#Preview {
    TaskBoardView()
        .environmentObject(TaskBoardStore(previewTasks: TaskItem.fixtures()))
        .environmentObject(AuthStore())
        .environmentObject(HouseholdStore())
        .environmentObject(TagStore(householdStore: HouseholdStore()))
}
