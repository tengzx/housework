import SwiftUI

@MainActor
struct WatchTimeTrackerView: View {
    @ObservedObject private var store = ShortcutRecordStore.shared
    @State private var shortcutTasks: [ShortcutTask] = []
    @State private var isLoadingShortcuts = false
    @State private var statusMessage = ""

    var body: some View {
        Group {
            if store.activeSession != nil {
                activeSessionView
            } else {
                shortcutList
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchDesign.stage.ignoresSafeArea())
        .task {
            await refreshRunningSession()
            await refreshShortcuts()
        }
    }

    @ViewBuilder
    private var activeSessionView: some View {
        if let session = store.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 0) {
                    Text(session.task.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(WatchDesign.green)
                            .frame(width: 7, height: 7)
                            .watchPulse()

                        Text("进行中 · \(startTimeText(session.startedAt)) 开始")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(WatchDesign.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.top, 6)

                    Text(timerText(from: session.startedAt, now: timeline.date))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 8)

                    Spacer(minLength: 28)

                    dock

                    let activeStatus = store.syncStatusMessage.isEmpty ? statusMessage : store.syncStatusMessage
                    if !activeStatus.isEmpty {
                        Text(activeStatus)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WatchDesign.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var shortcutList: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("选择一个活动，快速开始记录")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(WatchDesign.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)

                if shortcutTasks.isEmpty && !isLoadingShortcuts {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WatchDesign.muted)
                        Text("暂无快捷指令")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(statusMessage.isEmpty ? "下拉刷新" : statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WatchDesign.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(shortcutTasks) { task in
                        shortcutRow(task)
                    }
                }

                let activeStatus = store.syncStatusMessage.isEmpty ? statusMessage : store.syncStatusMessage
                if !activeStatus.isEmpty && !shortcutTasks.isEmpty {
                    Text(activeStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WatchDesign.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable { await refreshShortcuts() }
        .navigationTitle("快捷开始")
    }

    private func shortcutRow(_ task: ShortcutTask) -> some View {
        Button {
            startTask(task)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(task.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(subtitle(for: task))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WatchDesign.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(task.color)
                    .frame(width: 32, height: 32)
                    .background(task.color.opacity(0.22), in: Circle())
            }
            .padding(.horizontal, 10)
            .frame(height: 62)
            .background(WatchDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(WatchPressButtonStyle())
    }

    /// "生活 · 常用" or "出行 · 预计 30 分钟" — big-category label plus usage/estimate.
    private func subtitle(for task: ShortcutTask) -> String {
        let category = task.categoryName?.trimmingCharacters(in: .whitespaces)
        let tail: String
        if let minutes = task.defaultDurationMinutes, minutes > 0 {
            tail = "预计 \(minutes) 分钟"
        } else {
            tail = "常用"
        }
        if let category, !category.isEmpty {
            return "\(category) · \(tail)"
        }
        return tail
    }

    private var dock: some View {
        Button {
            stopActiveSession()
        } label: {
            Text("结束记录")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(WatchDesign.accent, in: Capsule())
        }
        .buttonStyle(WatchPressButtonStyle())
        .accessibilityLabel("结束当前记录")
    }

    private func startTask(_ task: ShortcutTask) {
        statusMessage = ""
        store.start(task)
        #if os(watchOS)
        WatchAuthSync.shared.broadcastTimeEntry(store.sharedActiveActivity())
        #endif
    }

    private func stopActiveSession() {
        statusMessage = ""
        store.stop(note: "")
        #if os(watchOS)
        WatchAuthSync.shared.broadcastTimeEntry(nil)
        #endif
    }

    private func refreshRunningSession() async {
        do {
            let runningEntry = try await ShortcutAPI.running()
            store.syncRunningSession(runningEntry)
        } catch {
            statusMessage = "读取失败"
        }
    }

    private func refreshShortcuts() async {
        guard !isLoadingShortcuts else { return }
        isLoadingShortcuts = true
        defer { isLoadingShortcuts = false }

        do {
            // Primary source: the user's shortcut list (same endpoint as the phone).
            let remote = try await ShortcutAPI.listShortcuts()
            let remoteTasks = remote.map { ShortcutTask(remote: $0) }
            if !remoteTasks.isEmpty {
                shortcutTasks = remoteTasks
            } else {
                // No shortcuts yet: fall back to category-derived tasks so the
                // watch still offers something to start.
                let categories = (try? await ShortcutAPI.categories()) ?? []
                let derived = Self.tasks(from: categories)
                shortcutTasks = derived.isEmpty ? store.tasks : derived
            }
            statusMessage = ""
        } catch {
            if shortcutTasks.isEmpty {
                shortcutTasks = store.tasks
            }
            statusMessage = "快捷指令读取失败"
        }
    }

    private static func tasks(from categories: [ShortcutCategory]) -> [ShortcutTask] {
        categories.flatMap { category in
            if category.subtypes.isEmpty {
                return [
                    ShortcutTask(
                        name: category.label,
                        symbolName: symbolName(for: category.label),
                        colorHex: category.colorHex,
                        categoryId: category.id,
                        subtypeId: nil,
                        categoryName: category.label
                    )
                ]
            }

            return category.subtypes.map { subtype in
                ShortcutTask(
                    name: subtype.label,
                    symbolName: symbolName(for: subtype.label),
                    colorHex: category.colorHex,
                    categoryId: category.id,
                    subtypeId: subtype.id,
                    categoryName: category.label
                )
            }
        }
    }

    private static func symbolName(for label: String) -> String {
        let mappings: [(String, String)] = [
            ("编程", "chevron.left.forwardslash.chevron.right"),
            ("代码", "chevron.left.forwardslash.chevron.right"),
            ("会议", "briefcase.fill"),
            ("写作", "pencil"),
            ("设计", "paintbrush.fill"),
            ("阅读", "book.fill"),
            ("课程", "graduationcap.fill"),
            ("笔记", "note.text"),
            ("练习", "checklist"),
            ("吃饭", "fork.knife"),
            ("购物", "cart.fill"),
            ("通勤", "car.fill"),
            ("家务", "house.fill"),
            ("健身", "dumbbell.fill"),
            ("跑步", "figure.run"),
            ("瑜伽", "figure.mind.and.body"),
            ("睡眠", "moon.stars.fill"),
            ("冥想", "figure.mind.and.body"),
            ("游戏", "gamecontroller.fill"),
            ("音乐", "music.note"),
            ("视频", "video.fill"),
            ("社交", "heart.fill")
        ]

        return mappings.first { label.contains($0.0) }?.1 ?? "bolt.fill"
    }

    private func startTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func timerText(from startDate: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct WatchPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

private struct WatchPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 1 : 0.4)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

private extension View {
    func watchPulse() -> some View {
        modifier(WatchPulseModifier())
    }
}

private enum WatchDesign {
    static let stage = Color(hex: "0B0B0C")
    static let surface = Color(hex: "1C1C1E")
    static let line = Color(hex: "2C2C2E")
    static let muted = Color(hex: "8A8F9C")
    static let brand = Color(hex: "5A5E68")
    static let accentHex = "FF7847"
    static let accent = Color(hex: accentHex)
    static let green = Color(hex: "22C55E")
    static let stop = Color(hex: "FF453A")
}

private struct WatchTimeTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        WatchTimeTrackerView()
            .previewDisplayName("Apple Watch Time Tracker")
    }
}
