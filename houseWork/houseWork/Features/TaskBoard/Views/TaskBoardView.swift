//
//  TaskBoardView.swift
//  houseWork
//
//  Displays the current household workload grouped by status.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TaskBoardView: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.locale) private var locale
    @State private var dragOffsetX: CGFloat = 0
    
    var body: some View {
        navigationContainer {
            ZStack(alignment: .bottomTrailing) {
                List {
                    headerSection
                    boardContent
                }
                .listStyle(.plain)
                .applyScrollContentBackgroundHidden()
                .background(Color(.systemGroupedBackground))
                .refreshable {
                    await viewModel.refreshTasks()
                }
                floatingAddButton
            }
            .background(Color(.systemGroupedBackground))
        }
        .hideNavigationBar()
        .alert(
            LocalizedStringKey("taskBoard.error.title"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: {
                Button(LocalizedStringKey("common.ok"), role: .cancel) { }
            },
            message: {
                Text(viewModel.alertMessage ?? "")
            }
        )
        .sheet(isPresented: $viewModel.showingTaskComposer) {
            TaskComposerView()
                .environmentObject(viewModel.taskStore)
                .environmentObject(viewModel.authStore)
                .environmentObject(viewModel.tagStore)
        }
        .sheet(item: $viewModel.inspectingTask) { task in
            TaskDetailView(task: task)
        }
        .sheet(item: $viewModel.editingTask) { task in
            TaskEditorView(task: task)
                .environmentObject(viewModel.taskStore)
                .environmentObject(viewModel.tagStore)
        }
    }
    
    private var headerSection: some View {
        Section {
            weekCalendar
            filterPicker
            summaryRow
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    @ViewBuilder
    private var boardContent: some View {
        if viewModel.isLoading && viewModel.filteredTasks.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView(LocalizedStringKey("taskBoard.loading"))
                        .padding(.vertical, 40)
                    Spacer()
                }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            if viewModel.filteredTasks.isEmpty {
                Section {
                    placeholderView(
                        title: LocalizedStringKey("taskBoard.placeholder.empty"),
                        systemImage: "tray"
                    )
                    .frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                let visibleSections = viewModel.visibleSections
                if visibleSections.isEmpty {
                    Section {
                        placeholderView(title: LocalizedStringKey("taskBoard.placeholder.nomatch"), systemImage: "tray")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                
                ForEach(viewModel.visibleSections) { section in
                    taskSectionView(for: section)
                }
            }
        }
    }
    
    private var floatingAddButton: some View {
        Button {
            Haptics.impact()
            viewModel.presentComposer()
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
        .accessibilityLabel(Text(LocalizedStringKey("taskBoard.button.add")))
    }
    
    private var householdHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(viewModel.householdStore.households) { summary in
                    Button {
                        viewModel.householdStore.select(summary)
                    } label: {
                        HStack {
                            Text(summary.name)
                            if summary.id == viewModel.householdStore.householdId {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.householdStore.householdName)
                            .font(.title2.bold())
                        Text("household.id.format \(viewModel.householdStore.householdId)")
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
    
    private var weekCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let relativeKey = headerDateRelativeKey(for: viewModel.selectedDate) {
                Text(relativeKey)
                    .font(.title2.bold())
            } else {
                Text(formattedHeaderDate(for: viewModel.selectedDate, locale: locale))
                    .font(.title2.bold())
            }
            CalendarStripView(
                dates: viewModel.calendarDates,
                selectedDate: viewModel.selectedDate,
                locale: locale,
                onSelect: { date in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectDate(date)
                    }
                },
                onPreviousWeek: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.showPreviousWeek()
                    }
                    Haptics.impact()
                },
                onNextWeek: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.showNextWeek()
                    }
                    Haptics.impact()
                }
            )
        }
    }
    
    private var filterPicker: some View {
        Picker(LocalizedStringKey("taskBoard.filter.label"), selection: $viewModel.selectedFilter) {
            ForEach(TaskBoardFilter.allCases) { filter in
                Text(filter.labelKey).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var summaryRow: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 160), spacing: 12), count: 2)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.statusSegments) { segment in
                Button {
                    viewModel.selectedStatus = segment.status
                } label: {
                    StatusSummaryCard(
                        title: segment.title,
                        value: "\(viewModel.taskCount(for: segment.status))",
                        icon: segment.icon,
                        background: segment.background,
                        isSelected: segment.status == viewModel.selectedStatus
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
                    isActionEnabled: viewModel.canMutate(task: task),
                    showsDetails: false
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    viewModel.inspectingTask = task
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        viewModel.editingTask = task
                    } label: {
                        Label(LocalizedStringKey("taskBoard.action.edit"), systemImage: "pencil")
                    }
                    .tint(.orange)
                    
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteTask(task)
                        }
                    } label: {
                        Label(LocalizedStringKey("taskBoard.action.delete"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 2)
            }
        }
    }

    private func primaryButton(for task: TaskItem) -> TaskCardButton? {
        guard viewModel.canMutate(task: task) else { return nil }
        switch task.status {
        case .backlog:
            return TaskCardButton(
                title: LocalizedStringKey("taskBoard.button.start"),
                systemImage: "play.circle.fill",
                style: .borderedProminent
            ) {
                Task {
                    await viewModel.startTask(task)
                }
            }
        case .inProgress:
            return TaskCardButton(
                title: LocalizedStringKey("taskBoard.button.complete"),
                systemImage: "checkmark.circle.fill",
                style: .borderedProminent
            ) {
                Task {
                    await viewModel.completeTask(task)
                }
            }
        case .completed:
            return nil
        }
    }
    
    private func secondaryButton(for task: TaskItem) -> TaskCardButton? {
        guard viewModel.canMutate(task: task) else { return nil }
        switch task.status {
        case .backlog:
            return TaskCardButton(
                title: LocalizedStringKey("taskBoard.button.quickDone"),
                systemImage: "checkmark.circle",
                style: .bordered
            ) {
                Task {
                    await viewModel.quickComplete(task)
                }
            }
        case .inProgress, .completed:
            return nil
        }
    }
    
}

private struct StatusSummaryCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let background: Color?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.primary)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.title.bold())
                .foregroundStyle(Color.primary.opacity(0.9))
                .frame(alignment: .center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.primary.opacity(0.25) : .clear, lineWidth: 2)
        )
    }
    
    private var backgroundColor: Color {
        if let background {
            return Color(uiColor: UIColor(dynamicProvider: { trait in
                let light = background
                let dark = background.opacity(0.35)
                return trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }))
        }
        return Color(.secondarySystemBackground)
    }
}

@ViewBuilder
private func placeholderView(title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey? = nil) -> some View {
    if #available(iOS 17.0, *) {
        if let description {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    } else {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    
    var body: some View {
        navigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusRow
                    detailRow(title: LocalizedStringKey("taskBoard.detail.dueDate"), value: task.dueDate.formatted(date: .abbreviated, time: .shortened))
                    detailRow(title: LocalizedStringKey("taskBoard.detail.roomTag"), value: task.roomTag)
                    detailRow(title: LocalizedStringKey("taskBoard.detail.score"), value: "\(task.score)")
                    detailRow(title: LocalizedStringKey("taskBoard.detail.estimatedMinutes"), value: "\(task.estimatedMinutes)")
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey("taskBoard.detail.section.details"))
                            .font(.headline)
                        Text(task.details)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey("taskBoard.detail.section.members"))
                            .font(.headline)
                        if task.assignedMembers.isEmpty {
                            Text(LocalizedStringKey("task.unassigned"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(task.assignedMembers, id: \.id) { member in
                                HStack(spacing: 12) {
                                    MemberAvatarView(member: member, size: 36)
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
                    Button(LocalizedStringKey("taskBoard.detail.close")) { dismiss() }
                }
            }
        }
    }
    
    private var statusRow: some View {
        HStack {
            Label(task.status.labelKey, systemImage: task.status.iconName)
                .font(.headline)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(task.status.accentColor.opacity(0.2), in: Capsule())
            Spacer()
            Text(task.status == .completed ? LocalizedStringKey("taskBoard.detail.status.finished") : LocalizedStringKey("taskBoard.detail.status.active"))
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }
    
    private func detailRow(title: LocalizedStringKey, value: String) -> some View {
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
        navigationContainer {
            Form {
                Section(LocalizedStringKey("taskBoard.editor.section.basics")) {
                    TextField(LocalizedStringKey("taskBoard.editor.field.title"), text: $title)
                    detailsField
                }
                
                Section(LocalizedStringKey("taskBoard.editor.section.scheduling")) {
                    DatePicker(LocalizedStringKey("taskBoard.detail.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text(LocalizedStringKey("taskBoard.editor.field.estimatedTime"))
                        Spacer()
                        TextField(LocalizedStringKey("taskBoard.editor.field.estimatedTime"), value: $estimatedMinutes, format: .number)
                            .multilineTextAlignment(.trailing)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .frame(width: 80)
                        Stepper("", value: $estimatedMinutes, in: 5...240, step: 5)
                            .labelsHidden()
                    }
                    HStack {
                        Text(LocalizedStringKey("taskBoard.editor.field.score"))
                        Spacer()
                        TextField(LocalizedStringKey("taskBoard.editor.field.score"), value: $score, format: .number)
                            .multilineTextAlignment(.trailing)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .frame(width: 80)
                        Stepper("", value: $score, in: 5...100, step: 5)
                            .labelsHidden()
                    }
                }
                
                Section(LocalizedStringKey("taskBoard.editor.section.tags")) {
                    Picker(LocalizedStringKey("taskBoard.editor.field.roomTag"), selection: $roomTag) {
                        Text(LocalizedStringKey("taskBoard.editor.field.general")).tag("General")
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
            .navigationTitle(LocalizedStringKey("taskBoard.editor.nav.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("common.save"), action: saveTask)
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    @ViewBuilder
    private var detailsField: some View {
        if #available(iOS 16.0, *) {
            TextField(LocalizedStringKey("taskBoard.editor.field.details"), text: $details, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        } else {
            TextEditor(text: $details)
                .frame(minHeight: 80)
        }
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
                details: trimmedDetails.isEmpty ? String(localized: "task.details.empty") : trimmedDetails,
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
                    errorMessage = taskStore.mutationError ?? String(localized: "taskBoard.editor.error.saveFailed")
                }
            }
        }
    }
}

#Preview {
    let householdStore = HouseholdStore()
    let tagStore = TagStore(householdStore: householdStore)
    let authStore = AuthStore()
    let taskStore = TaskBoardStore(previewTasks: TaskItem.fixtures())
    let memberDirectory = MemberDirectory(profileService: InMemoryUserProfileService())
    return TaskBoardView(
        viewModel: TaskBoardViewModel(
            taskStore: taskStore,
            authStore: authStore,
            householdStore: householdStore,
            tagStore: tagStore,
            memberDirectory: memberDirectory
        )
    )
}

private extension View {
    @ViewBuilder
    func applyScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

private func weekdayText(for date: Date, locale: Locale) -> String {
    if locale.languageCode?.hasPrefix("zh") == true {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    } else {
        var calendar = Calendar.current
        calendar.locale = locale
        let weekday = calendar.component(.weekday, from: date)
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return symbols[(weekday - 1) % symbols.count]
    }
}

private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "d"
    return formatter
}()

private func headerDateRelativeKey(for date: Date) -> LocalizedStringKey? {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return LocalizedStringKey("taskBoard.header.today")
    }
    if calendar.isDateInYesterday(date) {
        return LocalizedStringKey("taskBoard.header.yesterday")
    }
    if calendar.isDateInTomorrow(date) {
        return LocalizedStringKey("taskBoard.header.tomorrow")
    }
    return nil
}

private func formattedHeaderDate(for date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    if locale.languageCode?.hasPrefix("zh") == true {
        formatter.dateFormat = "M月d日"
    } else {
        formatter.dateFormat = "MMM d"
    }
    return formatter.string(from: date)
}

private struct CalendarStripView: View {
    let dates: [Date]
    let selectedDate: Date
    let locale: Locale
    let onSelect: (Date) -> Void
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    @State private var pageSelection: Int = 1
    
    var body: some View {
        if dates.isEmpty {
            EmptyView()
                .frame(height: 80)
        } else {
            TabView(selection: $pageSelection) {
                weekView(for: weekDates(offset: -7))
                    .tag(0)
                weekView(for: dates)
                    .tag(1)
                weekView(for: weekDates(offset: 7))
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 80)
            .onAppear {
                pageSelection = 1
            }
            .onChange(of: dates.first) { _ in
                pageSelection = 1
            }
            .onChange(of: pageSelection) { newValue in
                switch newValue {
                case 0:
                    onPreviousWeek()
                    pageSelection = 1
                case 2:
                    onNextWeek()
                    pageSelection = 1
                default:
                    break
                }
            }
        }
    }
    
    @ViewBuilder
    private func weekView(for week: [Date]) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let horizontalInset: CGFloat = 16
            let columns = CGFloat(max(week.count, 1))
            let availableWidth = max(proxy.size.width - (horizontalInset * 2), 0)
            let baseWidth = max(
                (availableWidth - spacing * CGFloat(max(0, week.count - 1))) / columns,
                0
            )
            let cellWidth = min(56, baseWidth)
            
            HStack(spacing: spacing) {
                ForEach(week, id: \.self) { date in
                    Button {
                        Haptics.impact()
                        onSelect(date)
                    } label: {
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        let isToday = Calendar.current.isDateInToday(date)
                        
                        VStack(spacing: 4) {
                            Text(weekdayText(for: date, locale: locale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(dayFormatter.string(from: date))
                                .font(.body)
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundStyle(isToday ? Color.primary : Color.secondary)
                        }
                        .frame(width: cellWidth, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color(.systemGray5) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    borderColor(isSelected: isSelected, isToday: isToday),
                                    lineWidth: borderWidth(isSelected: isSelected, isToday: isToday)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 4)
        }
        .frame(height: 80)
    }
    
    private func weekDates(offset: Int) -> [Date] {
        guard let anchor = dates.first,
              let start = Calendar.current.date(byAdding: .day, value: offset, to: anchor) else {
            return []
        }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    
    private func borderColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return Color.clear
        }
        if isToday {
            return Color.accentColor.opacity(0.3)
        }
        return Color.clear
    }
    
    private func borderWidth(isSelected: Bool, isToday: Bool) -> CGFloat {
        if isSelected {
            return 0
        }
        if isToday {
            return 1
        }
        return 0
    }
}
