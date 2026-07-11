import SwiftUI

@MainActor
struct RecordView: View {
    @ObservedObject var calendarStore: TimeCalendarStore
    @ObservedObject var dashboardVM: TimeDashboardViewModel
    @ObservedObject private var store = ShortcutRecordStore.shared
    @State private var text = ""
    @State private var isAdding = false
    @State private var isManagingShortcuts = false
    @State private var editingTask: ShortcutTask?
    @State private var statusMessage = ""
    @State private var showCalendar = false
    @State private var showIdealDay = false
    @State private var showDashboard = false
    @ObservedObject private var idealDayStore = IdealDayStore.shared
    @ObservedObject private var intentionStore = DailyIntentionStore.shared
    @State private var isAddingIntention = false
    @FocusState private var isInputFocused: Bool

    /// How many intentions the collapsed list shows.
    private static let collapsedIntentionCount = 2

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Design.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.bottom, 18)

                    activeCard
                        .padding(.bottom, 18)

                    inputBar
                        .padding(.bottom, 18)

                    intentionsSection
                        .padding(.bottom, 18)

                    sectionHeader
                        .padding(.bottom, 12)

                    shortcutsGrid

                    let displayStatus = store.syncStatusMessage.isEmpty ? statusMessage : store.syncStatusMessage
                    if !displayStatus.isEmpty {
                        Text(displayStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(displayStatus.contains("失败") ? .red : Design.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: 430)
            }
            .collapsibleTabScroll()
            .scrollDismissesKeyboard(.immediately)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                isInputFocused = false
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $isAdding) {
            AddShortcutSheet(store: store, calendarStore: calendarStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(item: $editingTask) { task in
            AddShortcutSheet(store: store, calendarStore: calendarStore, editingTask: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showCalendar) {
            CalendarTrackerView2(store: calendarStore)
        }
        .sheet(isPresented: $showIdealDay) {
            IdealDayView(store: idealDayStore)
        }
        .sheet(isPresented: $showDashboard) {
            TimeDashboardView(viewModel: dashboardVM)
        }
        .sheet(isPresented: $isAddingIntention) {
            IntentionBoardSheet(store: intentionStore, onStart: { item in
                startIntention(item)
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .task {
            await refreshRunningSession()
            await store.refreshTasks()
            await intentionStore.refresh()
            await idealDayStore.load()
            await IdealDayReminderScheduler.reschedule(profile: idealDayStore.profile)
        }
        .tint(Design.accent)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(Self.todayText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Design.text)

            Spacer()

            HStack(spacing: 10) {
                headerIconButton(symbol: "calendar") {
                    isInputFocused = false
                    showCalendar = true
                }
                headerIconButton(symbol: "sun.max.fill") {
                    isInputFocused = false
                    showIdealDay = true
                }
                headerIconButton(symbol: "chart.bar.fill") {
                    isInputFocused = false
                    showDashboard = true
                }
            }
        }
    }

    private func headerIconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.icon)
                .frame(width: 40, height: 40)
                .background(Design.surface, in: Circle())
                .overlay(Circle().stroke(Design.line, lineWidth: 1))
        }
        .buttonStyle(PressButtonStyle())
    }

    private var activeCard: some View {
        Group {
            if let session = store.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Design.green)
                                        .frame(width: 9, height: 9)
                                        .pulse()

                                    Text("进行中")
                                        .font(.system(size: 12, weight: .regular))
                                        .tracking(2)
                                        .foregroundStyle(Design.muted)
                                }
                                .padding(.bottom, 12)

                                Text(session.task.name)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Design.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.bottom, 6)

                                Text(timerText(from: session.startedAt, now: timeline.date))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .tracking(1)
                                    .foregroundStyle(Design.text)
                            }

                            Spacer(minLength: 8)

                            progressRing(progress: ringProgress(session: session, now: timeline.date))
                        }

                        Button {
                            stopActiveSession()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("结束")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Design.stopFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressButtonStyle())
                    }
                    .padding(18)
                    .background(Design.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Design.line, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .shadow(color: .black.opacity(0.05), radius: 24, y: 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("还没有开始")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Design.text)

                    Text("点一个快捷指令，或在下面输入正在做的事")
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(Design.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Design.line, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
            }
        }
    }

    /// Circular clock shown in the active card — replicates the prototype: a
    /// dashed tick ring on the outside, a blue progress arc over it, and a
    /// centered analog clock with thick hands.
    private func progressRing(progress: Double) -> some View {
        TimerClockRing(
            progress: progress,
            tickColor: Design.muted.opacity(0.5),
            arcColor: Design.accent,
            handColor: Design.text
        )
        .frame(width: 92, height: 92)
        .animation(.easeInOut(duration: 0.4), value: progress)
    }

    /// Ring fill: progress toward the shortcut's default duration when set,
    /// otherwise a gentle sweep over the current hour so the ring always reads
    /// as "live".
    private func ringProgress(session: ActiveShortcutSession, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(session.startedAt))
        if let minutes = session.task.defaultDurationMinutes, minutes > 0 {
            return min(1, elapsed / Double(minutes * 60))
        }
        return elapsed.truncatingRemainder(dividingBy: 3600) / 3600
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Design.accent)

            TextField(store.activeSession == nil ? "输入：刚刚开会 30 分钟" : "切换到新的事…", text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Design.text)
                .textInputAutocapitalization(.never)
                .focused($isInputFocused)
                .onSubmit {
                    submitText()
                }

            Button {
                isInputFocused = true
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Design.muted)
            }
            .buttonStyle(PressButtonStyle())

            Rectangle()
                .fill(Design.line)
                .frame(width: 1, height: 26)

            Button {
                submitText()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Design.accent, in: Circle())
            }
            .buttonStyle(PressButtonStyle())
            .disabled(trimmedText.isEmpty)
            .opacity(trimmedText.isEmpty ? 0.45 : 1)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .frame(height: 56)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Design.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
    }

    // MARK: - 今日意图

    private var intentionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("今日意图")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Design.muted)

                Spacer()

                Button {
                    isInputFocused = false
                    isAddingIntention = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("添加")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Design.accent)
                    .padding(4)
                }
                .buttonStyle(PressButtonStyle())
            }

            let all = intentionStore.sortedItems
            if all.isEmpty {
                Text("列出想推进的事，可挂到目标或项目上，点开始就计时")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Design.muted.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Design.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Design.line, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(all.prefix(Self.collapsedIntentionCount))) { item in
                        intentionRow(item)
                    }
                }

                if all.count > Self.collapsedIntentionCount {
                    Button {
                        isInputFocused = false
                        isAddingIntention = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("查看全部 (\(all.count))")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Design.muted)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }
        }
    }

    private func intentionRow(_ item: DailyIntentionItem) -> some View {
        let isRunning = intentionStore.activeIntentionId == item.id && store.activeSession != nil
        return HStack(spacing: 12) {
            // Tapping the circle toggles completion without touching the timer.
            Button {
                isInputFocused = false
                intentionStore.setCompleted(item, !item.isCompleted)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.isCompleted ? Design.green : Design.muted.opacity(0.55))
            }
            .buttonStyle(PressButtonStyle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Design.muted : (isRunning ? Design.accent : Design.text))
                    .strikethrough(item.isCompleted, color: Design.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let goalName = item.goalName {
                    HStack(spacing: 3) {
                        Image(systemName: item.goalKind == "project" ? "folder.fill" : "target")
                            .font(.system(size: 9, weight: .semibold))
                        Text(goalName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Design.muted.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            if item.isCompleted {
                Text("已完成")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.muted.opacity(0.82))
            } else if isRunning {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Design.green)
                        .frame(width: 8, height: 8)
                    Text("进行中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Design.accent)
                }
            } else {
                Button {
                    isInputFocused = false
                    startIntention(item)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Design.accent, in: Circle())
                }
                .buttonStyle(PressButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 58)
        .background(isRunning ? Design.accentSoft : Design.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isRunning ? Design.accent : Design.line, lineWidth: 1)
        )
        .opacity(item.isCompleted ? 0.65 : 1)
        .contextMenu {
            Button(role: .destructive) {
                intentionStore.remove(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    /// 开始 an intention: run it through the normal shortcut/time-entry flow
    /// (reusing a same-named shortcut's category when one exists) and remember
    /// the link so stopping the timer completes the intention.
    private func startIntention(_ item: DailyIntentionItem) {
        let task = store.tasks.first { $0.name == item.name }
            ?? ShortcutTask(name: item.name, symbolName: "target", colorHex: Design.accentHex)
        startTask(task, intention: item)
        intentionStore.linkActive(item)
    }

    private var sectionHeader: some View {
        HStack {
            Text("快捷开始")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Design.muted)

            Spacer()

            if !store.tasks.isEmpty {
                Button {
                    isInputFocused = false
                    isManagingShortcuts.toggle()
                } label: {
                    Text(isManagingShortcuts ? "完成" : "管理")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isManagingShortcuts ? Design.accent : Design.muted)
                        .padding(4)
                }
                .buttonStyle(PressButtonStyle())
            }

            Button {
                isInputFocused = false
                isAdding = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("新增")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Design.accent)
                .padding(4)
            }
            .buttonStyle(PressButtonStyle())
        }
    }

    private var shortcutsGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(store.tasks) { task in
                let isOn = store.activeSession?.task.id == task.id
                shortcutTile(task: task, isOn: isOn)
            }
        }
    }

    private func shortcutTile(task: ShortcutTask, isOn: Bool) -> some View {
        let tint = categoryColor(for: task)
        return HStack(spacing: 12) {
            Image(systemName: task.symbolName)
                .font(.system(size: 20, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? .white : tint.darkened(by: 0.12))
                .frame(width: 42, height: 42)
                .background(isOn ? tint : tint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Design.accent : Design.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(isManagingShortcuts ? "管理中" : (isOn ? "进行中" : "一键开始"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(isManagingShortcuts ? .red.opacity(0.72) : (isOn ? Design.accent : Design.muted.opacity(0.82)))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isManagingShortcuts {
                Button {
                    isInputFocused = false
                    editingTask = task
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Design.accent, in: Circle())
                }
                .buttonStyle(PressButtonStyle())

                Button {
                    isInputFocused = false
                    deleteTask(task)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.78), in: Circle())
                }
                .buttonStyle(PressButtonStyle())
            } else if isOn {
                Circle()
                    .fill(Design.green)
                    .frame(width: 8, height: 8)
            } else {
                Button {
                    isInputFocused = false
                    startTask(task)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Design.accent, in: Circle())
                }
                .buttonStyle(PressButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(isOn ? Design.accentSoft : Design.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isOn ? Design.accent : Design.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.035), radius: 18, y: 8)
    }

    /// Icon tint for a shortcut, taken from its 大类 (big category) color so the
    /// grid mirrors the category palette. Falls back to the task's own color when
    /// the category can't be resolved.
    private func categoryColor(for task: ShortcutTask) -> Color {
        if let id = task.categoryId,
           let category = calendarStore.categories.first(where: { $0.id == id }) {
            return category.color
        }
        return task.color
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitText() {
        let name = trimmedText
        guard !name.isEmpty else { return }
        text = ""
        isInputFocused = false
        let task = ShortcutTask(name: name, symbolName: "pencil", colorHex: Design.accentHex)
        startTask(task)
    }

    private func startTask(_ task: ShortcutTask, intention: DailyIntentionItem? = nil) {
        statusMessage = ""
        // Starting anything detaches the previous intention link; startIntention
        // re-links right after when the start came from an intention row.
        intentionStore.clearActiveLink()
        calendarStore.clearMobileAppEvents()
        store.start(task, intentionRemoteId: intention?.remoteId, intentionLocalId: intention?.id)
        PhoneWatchSync.shared.broadcastTimeEntry(store.sharedActiveActivity())
    }

    private func deleteTask(_ task: ShortcutTask) {
        store.removeTask(task)
        if store.tasks.isEmpty {
            isManagingShortcuts = false
        }
    }

    private func stopActiveSession() {
        isInputFocused = false
        statusMessage = ""
        calendarStore.clearMobileAppEvents()
        store.stop(note: "")
        // Ending the timer completes the intention that started it (if any).
        intentionStore.completeActiveLink()
        PhoneWatchSync.shared.broadcastTimeEntry(nil)
    }

    private func refreshRunningSession() async {
        do {
            let runningEntry = try await ShortcutAPI.running()
            store.syncRunningSession(runningEntry)
        } catch {
            statusMessage = "读取进行中失败：\(error.localizedDescription)"
        }
    }

    private func timerText(from startDate: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private static var todayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: .now)
    }
}

/// The intention board: every goal/project as a collapsible group with its
/// intentions inside (incomplete first, completed after). Both 查看全部 and
/// 添加 open this sheet. The + on a group inserts an inline draft row that is
/// saved on return / focus loss, or silently discarded when left empty.
@MainActor
private struct IntentionBoardSheet: View {
    @ObservedObject var store: DailyIntentionStore
    /// Starts the timer for an intention (provided by RecordView).
    let onStart: (DailyIntentionItem) -> Void

    @ObservedObject private var recordStore = ShortcutRecordStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Goal ids currently collapsed (nil = the 公共 group).
    @State private var collapsedGroups: Set<Int?> = []
    /// Inline draft state: which group the empty row lives in.
    @State private var isDrafting = false
    @State private var draftGoalId: Int?
    @State private var draftText = ""
    @FocusState private var isDraftFocused: Bool

    // Inline goal/project creation.
    @State private var isCreatingGoal = false
    @State private var newGoalName = ""
    @State private var newGoalKind = "goal"
    @State private var isSavingGoal = false
    @State private var goalErrorMessage = ""
    @FocusState private var isGoalNameFocused: Bool
    /// Goal pending delete confirmation (set by long-pressing a group header).
    @State private var goalToDelete: RemoteGoal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isCreatingGoal {
                    goalCreator
                }

                ForEach(store.goals) { goal in
                    groupSection(goal: goal)
                }
                groupSection(goal: nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Calendar2Style.sheet)
        .task {
            await store.loadGoals()
            await store.refresh()
        }
        .onChange(of: isDraftFocused) { _, focused in
            // Leaving the field commits a non-empty draft and silently drops an
            // empty one.
            if !focused, isDrafting {
                commitDraft()
            }
        }
        .confirmationDialog(
            "删除「\(goalToDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { goalToDelete != nil },
                set: { if !$0 { goalToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: goalToDelete
        ) { goal in
            Button("删除\(goal.isProject ? "项目" : "目标")", role: .destructive) {
                store.deleteGoal(goal)
                goalToDelete = nil
            }
            Button("取消", role: .cancel) {
                goalToDelete = nil
            }
        } message: { _ in
            Text("其下的意图不会删除，会移到「公共」")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Calendar2Style.accent)
            Text("意图 · 目标推进")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "23232A"))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCreatingGoal.toggle()
                }
                if isCreatingGoal {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isGoalNameFocused = true
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCreatingGoal ? "chevron.up" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isCreatingGoal ? "收起" : "新建目标")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Calendar2Style.accent)
                .padding(4)
            }
            .buttonStyle(HapticButtonStyle())
        }
    }

    // MARK: - Goal group

    private func groupSection(goal: RemoteGoal?) -> some View {
        let goalId = goal?.id
        let groupItems = store.boardItems(goalId: goalId)
        let doneCount = groupItems.filter(\.isCompleted).count
        let isCollapsed = collapsedGroups.contains(goalId)
        let isDraftingHere = isDrafting && draftGoalId == goalId

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isCollapsed {
                            collapsedGroups.remove(goalId)
                        } else {
                            collapsedGroups.insert(goalId)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "9A9AA2"))
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                        Image(systemName: goal == nil ? "tray" : (goal!.isProject ? "folder.fill" : "target"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Calendar2Style.accent)

                        Text(goal?.name ?? "公共")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: "2A2A30"))
                            .lineLimit(1)

                        if !groupItems.isEmpty {
                            Text("\(doneCount)/\(groupItems.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "9A9AA2"))
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HapticButtonStyle())
                .contextMenu {
                    if let goal {
                        Button(role: .destructive) {
                            goalToDelete = goal
                        } label: {
                            Label("删除\(goal.isProject ? "项目" : "目标")", systemImage: "trash")
                        }
                    }
                }

                Button {
                    beginDraft(goalId: goalId)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Calendar2Style.accent)
                        .frame(width: 30, height: 30)
                        .background(Calendar2Style.accent.opacity(0.1), in: Circle())
                }
                .buttonStyle(HapticButtonStyle())
            }

            if !isCollapsed {
                VStack(spacing: 8) {
                    if isDraftingHere {
                        draftRow
                    }
                    ForEach(groupItems) { item in
                        boardRow(item)
                    }
                    if groupItems.isEmpty && !isDraftingHere {
                        Text("还没有意图，点 + 添加")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(hex: "B5B5BC"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func boardRow(_ item: DailyIntentionItem) -> some View {
        let isRunning = store.activeIntentionId == item.id && recordStore.activeSession != nil
        return HStack(spacing: 11) {
            Button {
                store.setCompleted(item, !item.isCompleted)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(item.isCompleted ? Color(hex: "22C55E") : Color(hex: "C9C9CF"))
            }
            .buttonStyle(HapticButtonStyle())

            Text(item.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.isCompleted ? Color(hex: "9A9AA2") : (isRunning ? Calendar2Style.accent : Color(hex: "2A2A30")))
                .strikethrough(item.isCompleted, color: Color(hex: "9A9AA2"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            if isRunning {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "22C55E"))
                        .frame(width: 8, height: 8)
                    Text("进行中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Calendar2Style.accent)
                }
            } else if !item.isCompleted {
                Button {
                    onStart(item)
                    dismiss()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 31, height: 31)
                        .background(Calendar2Style.accent, in: Circle())
                }
                .buttonStyle(HapticButtonStyle())
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 52)
        .background(
            isRunning ? Calendar2Style.accent.opacity(0.08) : Color(hex: "F5F5F7"),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isRunning ? Calendar2Style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .opacity(item.isCompleted ? 0.62 : 1)
        .contextMenu {
            Button(role: .destructive) {
                store.remove(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// The inline empty row the + button creates: type and hit return to save;
    /// leave it empty and it disappears.
    private var draftRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "circle")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Color(hex: "C9C9CF"))

            TextField("输入意图，回车保存", text: $draftText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isDraftFocused)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "2A2A30"))
                .submitLabel(.done)
                .onSubmit {
                    commitDraft()
                }
        }
        .padding(.horizontal, 13)
        .frame(height: 52)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Calendar2Style.accent.opacity(0.45), lineWidth: 1.5)
        )
    }

    private func beginDraft(goalId: Int?) {
        // Commit any draft already in progress before opening a new one.
        if isDrafting {
            commitDraft()
        }
        draftGoalId = goalId
        draftText = ""
        isDrafting = true
        collapsedGroups.remove(goalId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isDraftFocused = true
        }
    }

    private func commitDraft() {
        let name = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            store.add(name: name, goal: store.goals.first { $0.id == draftGoalId })
        }
        draftText = ""
        isDrafting = false
        isDraftFocused = false
    }

    // MARK: - Inline goal creation

    private var goalCreator: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("目标或项目名称", text: $newGoalName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isGoalNameFocused)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Calendar2Style.sheet, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
                )

            HStack(spacing: 10) {
                Picker("类型", selection: $newGoalKind) {
                    Text("目标").tag("goal")
                    Text("项目").tag("project")
                }
                .pickerStyle(.segmented)

                Button {
                    createGoal()
                } label: {
                    Group {
                        if isSavingGoal {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("创建")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 34)
                    .background(
                        newGoalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Calendar2Style.faint : Calendar2Style.accent,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(Calendar2PressStyle())
                .disabled(newGoalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingGoal)
            }

            if !goalErrorMessage.isEmpty {
                Text(goalErrorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color(hex: "F5F5F7"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func createGoal() {
        let goalName = newGoalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goalName.isEmpty, !isSavingGoal else { return }
        isSavingGoal = true
        goalErrorMessage = ""
        Task {
            defer { isSavingGoal = false }
            do {
                _ = try await store.createGoal(name: goalName, kind: newGoalKind)
                newGoalName = ""
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCreatingGoal = false
                }
            } catch {
                goalErrorMessage = "创建失败：\(error.localizedDescription)"
            }
        }
    }
}

@MainActor
private struct AddShortcutSheet: View {
    @ObservedObject var store: ShortcutRecordStore
    @ObservedObject var calendarStore: TimeCalendarStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pickedCategory: String
    @State private var pickedSubtype: String?
    @State private var showManagement = false
    @State private var managementTab: ManagementTab = .category
    @FocusState private var isNameFocused: Bool

    private let editingTask: ShortcutTask?

    init(store: ShortcutRecordStore, calendarStore: TimeCalendarStore, editingTask: ShortcutTask? = nil) {
        self.store = store
        self.calendarStore = calendarStore
        self.editingTask = editingTask
        if let editingTask {
            _name = State(initialValue: editingTask.name)
            _pickedCategory = State(initialValue: editingTask.categoryId ?? calendarStore.categories.first?.id ?? "")
            _pickedSubtype = State(initialValue: editingTask.subtypeId)
        } else {
            let first = calendarStore.categories.first
            _pickedCategory = State(initialValue: first?.id ?? "")
            _pickedSubtype = State(initialValue: first?.types.first?.id)
        }
    }

    private var category: Calendar2Category {
        calendarStore.categories.first { $0.id == pickedCategory }
            ?? calendarStore.category(for: pickedCategory)
    }

    /// The currently selected small category (type), if any.
    private var pickedType: Calendar2CategoryType? {
        category.types.first { $0.id == pickedSubtype }
    }

    /// Icon auto-derived from the chosen 大类/小类 — no manual picking. Prefers
    /// the small category's backend icon, then the big category's, then a guess
    /// from the name.
    private var derivedSymbol: String {
        ShortcutRecordStore.resolvedSymbol(
            typeIcon: pickedType?.icon,
            categoryIcon: category.icon,
            name: trimmedName
        )
    }

    /// Color auto-derived from the chosen 小类 (falling back to the 大类).
    private var derivedColor: Color {
        pickedType?.color ?? category.color
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    nameField
                    categorySection
                    subcategorySection
                    iconPreviewSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            saveBar
        }
        .background(Calendar2Style.sheet)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showManagement) {
            Calendar2ManagementSheet(
                initialTab: managementTab,
                store: calendarStore,
                onDone: {
                    let cats = calendarStore.categories
                    if !cats.contains(where: { $0.id == pickedCategory }) {
                        pickedCategory = cats.first?.id ?? pickedCategory
                        pickedSubtype = cats.first?.types.first?.id
                    } else if cats.first(where: { $0.id == pickedCategory })?.types.contains(where: { $0.id == pickedSubtype }) == false {
                        pickedSubtype = cats.first(where: { $0.id == pickedCategory })?.types.first?.id
                    }
                }
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                isNameFocused = true
            }
        }
        .task {
            try? await calendarStore.reloadCategories()
            if let first = calendarStore.categories.first {
                if pickedCategory.isEmpty {
                    pickedCategory = first.id
                    pickedSubtype = first.types.first?.id
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.color)
                .frame(width: 13, height: 13)
            Text(editingTask == nil ? "新增快捷指令" : "编辑快捷指令")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "23232A"))
            Spacer()
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("名称")
            TextField("例如：写日记", text: $name)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isNameFocused)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "23232A"))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Calendar2Style.sheet, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Icon Preview (auto-derived from 大类/小类)

    private var iconPreviewSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("图标")
            HStack(spacing: 12) {
                Image(systemName: derivedSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(derivedColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(trimmedName.isEmpty ? "自动图标" : trimmedName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "2A2A30"))
                        .lineLimit(1)
                    Text("根据「\(category.label)\(pickedType.map { " · \($0.label)" } ?? "")」自动选择")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "9A9AA2"))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F5F5F7"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
            )
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionLabel("分类")
                Spacer()
                manageButton(tab: .category)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(calendarStore.categories) { item in
                    let isOn = pickedCategory == item.id
                    Button {
                        guard pickedCategory != item.id else { return }
                        pickedCategory = item.id
                        pickedSubtype = item.types.first?.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 9, height: 9)
                            Text(item.label)
                                .font(.system(size: 15, weight: isOn ? .semibold : .medium))
                                .foregroundStyle(isOn ? Color(hex: "2A2A30") : Color(hex: "4A4A52"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            isOn ? item.color.opacity(0.13) : Color(hex: "F5F5F7"),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isOn ? item.color.opacity(0.55) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(Calendar2PressStyle())
                }
            }
        }
    }

    // MARK: - Subcategory Section

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionLabel("小类 · \(category.label)")
                Spacer()
                manageButton(tab: .subcategory)
            }
            let types = category.types
            if types.isEmpty {
                Text("该分类暂无小类，点「管理」添加")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "B5B5BC"))
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(types) { type in
                        let isOn = pickedSubtype == type.id
                        let tint = category.color
                        Button { pickedSubtype = type.id } label: {
                            HStack(spacing: 8) {
                                Circle().fill(tint).frame(width: 9, height: 9)
                                Text(type.label)
                                    .font(.system(size: 15, weight: isOn ? .semibold : .medium))
                                    .foregroundStyle(isOn ? Color(hex: "2A2A30") : Color(hex: "4A4A52"))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                            .padding(.horizontal, 14)
                            .background(
                                isOn ? tint.opacity(0.13) : Color(hex: "F5F5F7"),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(isOn ? tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(Calendar2PressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
            Button { save() } label: {
                Text(editingTask == nil ? "保存指令" : "保存修改")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        trimmedName.isEmpty ? Calendar2Style.faint : Calendar2Style.accent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: trimmedName.isEmpty ? .clear : Calendar2Style.accent.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(Calendar2PressStyle())
            .disabled(trimmedName.isEmpty)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Calendar2Style.sheet.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Helpers

    private func manageButton(tab: ManagementTab) -> some View {
        Button {
            managementTab = tab
            showManagement = true
        } label: {
            HStack(spacing: 3) {
                Text("管理")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Calendar2Style.accent)
        }
        .buttonStyle(HapticButtonStyle())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(hex: "9A9AA2"))
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let categoryId = pickedCategory.isEmpty ? nil : pickedCategory
        // Icon + color are auto-derived from the chosen 大类/小类 — no manual pick.
        let derived = ShortcutTask(
            name: trimmedName,
            symbolName: derivedSymbol,
            colorHex: derivedColor.toHex() ?? ShortcutTask.defaultColorHex
        )
        if let editingTask {
            store.updateTask(editingTask, name: trimmedName, template: derived, categoryId: categoryId, subtypeId: pickedSubtype)
        } else {
            store.addTask(name: trimmedName, template: derived, categoryId: categoryId, subtypeId: pickedSubtype)
        }
        dismiss()
    }
}

/// The analog clock + progress ring in the active card. Drawn with Canvas so the
/// radial tick ring, the blue progress arc, and the thick hands match the
/// reference screenshot exactly.
private struct TimerClockRing: View {
    var progress: Double
    var tickColor: Color
    var arcColor: Color
    var handColor: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            // 1. Dashed radial tick ring (outermost).
            let tickCount = 60
            let tickOuter = radius
            let tickInner = radius - 5
            for i in 0..<tickCount {
                let angle = Double(i) / Double(tickCount) * 2 * .pi - .pi / 2
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * tickInner,
                                      y: center.y + sin(angle) * tickInner))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * tickOuter,
                                         y: center.y + sin(angle) * tickOuter))
                context.stroke(tick, with: .color(tickColor), lineWidth: 1.4)
            }

            // 2. Blue progress arc, sitting over the ticks at the outer edge.
            let arcRadius = radius - 2.5
            let sweep = 360 * max(0.02, min(1, progress))
            var arc = Path()
            arc.addArc(center: center,
                       radius: arcRadius,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + sweep),
                       clockwise: false)
            context.stroke(arc, with: .color(arcColor),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))

            // 3. Analog hands — minute to 3 o'clock, hour down to 6, matching the
            // screenshot. Thick with rounded caps.
            let handStyle = StrokeStyle(lineWidth: 4, lineCap: .round)
            var minute = Path()
            minute.move(to: center)
            minute.addLine(to: CGPoint(x: center.x + radius * 0.5, y: center.y))
            context.stroke(minute, with: .color(handColor), style: handStyle)

            var hour = Path()
            hour.move(to: center)
            hour.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.4))
            context.stroke(hour, with: .color(handColor), style: handStyle)
        }
    }
}

private struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Design.green.opacity(pulsing ? 0 : 0.5), radius: pulsing ? 6 : 0)
            .scaleEffect(pulsing ? 1.03 : 1)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear {
                pulsing = true
            }
    }
}

private extension View {
    func pulse() -> some View {
        modifier(PulseModifier())
    }
}

private enum Design {
    static let bg = Color(hex: "F5F6F8")
    static let surface = Color(hex: "FFFFFF")
    static let surface2 = Color(hex: "F0F1F4")
    static let line = Color(hex: "E9EBF0")
    static let text = Color(hex: "1E2333")
    static let muted = Color(hex: "8A8F9C")
    static let icon = Color(hex: "6F7480")
    static let iconSurface = Color(hex: "F7F8FA")
    static let iconLine = Color(hex: "EEF0F3")
    // Prototype primary is blue; the 结束 button is dark navy.
    static let accentHex = "0A84FF"
    static let accent = Color(hex: accentHex)
    static let accentSoft = Color(hex: "EAF4FF")
    // "结束" button: muted blue-gray slate with a white label.
    static let stopFill = Color(hex: "5A6479")
    static let green = Color(hex: "22C55E")
}
