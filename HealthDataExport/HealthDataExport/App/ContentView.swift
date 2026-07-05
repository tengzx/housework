import SwiftUI
import Combine

/// App-level state for a running workout. Holding it above the `TabView` lets the
/// active-session screen live at the app root, so it survives tab switches: it can
/// be collapsed into a floating bar (`isMinimized`) while the workout keeps running,
/// and re-opened later.
@MainActor
final class ActiveWorkoutStore: ObservableObject {
    /// The running workout's view-model. Owned here (not by the screen) so it
    /// survives collapsing the workout into the tab-bar accessory: re-opening the
    /// full screen reuses the same model, so its data isn't reloaded.
    @Published private(set) var vm: FitnessActiveSessionViewModel?
    @Published var isMinimized = false
    /// Live heart rate pushed from the watch during the active session.
    @Published var remoteHeartRate: Int?

    /// Broadcasts a local session change to the watch. nil = the workout ended.
    /// Set by the app root; not called while applying a change that came *from*
    /// the watch (so the two don't ping-pong).
    var onLocalChange: ((FitnessWorkoutSessionPayload?) -> Void)?
    private var applyingRemote = false

    func start(_ payload: FitnessWorkoutSessionPayload) {
        vm = FitnessActiveSessionViewModel(payload: payload)
        isMinimized = false
        remoteHeartRate = nil
        if !applyingRemote { onLocalChange?(payload) }
    }
    func minimize() { isMinimized = true }
    func restore() { isMinimized = false }
    func end() {
        let hadSession = vm != nil
        vm = nil
        isMinimized = false
        remoteHeartRate = nil
        if hadSession && !applyingRemote { onLocalChange?(nil) }
    }

    /// Open a workout that was started on the watch — minimized into the floating
    /// bar so it's present but unobtrusive. No-op if that session is already open.
    func applyRemoteStart(_ payload: FitnessWorkoutSessionPayload) {
        guard vm?.payload.sessionId != payload.sessionId else { return }
        applyingRemote = true
        vm = FitnessActiveSessionViewModel(payload: payload)
        isMinimized = true
        remoteHeartRate = nil
        applyingRemote = false
    }

    /// Close the workout because it finished on the watch.
    @discardableResult
    func applyRemoteEnd() -> Bool {
        guard vm != nil else { return false }
        applyingRemote = true
        end()
        applyingRemote = false
        return true
    }
}

struct ContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var fitnessSessionEvents: FitnessSessionEventStore
    @StateObject private var workout = ActiveWorkoutStore()
    @ObservedObject private var timeTracker = ShortcutRecordStore.shared
    // Persist the selected tab so collapsing the workout (which toggles the tab-bar
    // accessory) keeps the user on the tab they were on, not resetting to 记录.
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordWorkspaceView()
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabItem {
                    Label("记录", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(0)

            FitnessTemplateListView()
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabItem {
                    Label("健身", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(1)

            HealthExportView(
                configurationStore: dependencies.configurationStore,
                observerSyncManager: dependencies.healthObserverSyncManager
            )
            .tabBarMinimizeBehavior(.onScrollDown)
                .tabItem {
                    Label("数据", systemImage: "house")
                }
                .tag(2)

            ProfileTabView()
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(3)
        }
        .tint(Color(hex: "FF7847"))
        .environmentObject(workout)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Attach the collapsed-workout accessory to the tab bar ONLY while a workout
        // is minimized — otherwise the accessory chrome would show as an empty bar.
        // Applied as a conditional modifier on the same TabView so tab state is kept.
        .modifier(CollapsedWorkoutAccessory(workout: workout))
        // The full-screen workout is hosted above the tabs; re-opening reuses the
        // stored view-model, so no reload happens when expanding from the accessory.
        .overlay {
            if let vm = workout.vm, !workout.isMinimized {
                FitnessActiveSessionView(vm: vm) {
                    fitnessSessionEvents.sessionDidComplete()
                }
                .environmentObject(workout)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: workout.isMinimized)
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: workout.vm == nil)
        .task {
            // Keep the watch and phone showing the same active workout.
            workout.onLocalChange = { payload in
                PhoneWatchSync.shared.broadcastWorkout(
                    payload.map { WorkoutSyncPayload(sessionId: $0.sessionId, name: $0.name) }
                )
            }
            // Relay time-tracking changes to the watch face complication whenever
            // the phone's active entry is saved (started, switched, or stopped).
            SharedActivityStore.onWrite = { activity in
                PhoneWatchSync.shared.broadcastTimeEntry(activity)
            }
            // Catch up: if the phone already has a running entry mirrored, push it so
            // a freshly-launched watch converges. Only when non-nil — broadcasting a
            // stale `nil` here could wrongly clear a live entry on the watch.
            if let current = SharedActivityStore.read() ?? timeTracker.sharedActiveActivity() {
                PhoneWatchSync.shared.broadcastTimeEntry(current)
            }
            // Reflect time-tracking changes made on the watch, even when the
            // Record tab hasn't been opened yet.
            PhoneWatchSync.shared.onRemoteTimeEntry = { activity in
                Task { @MainActor in
                    timeTracker.applyRemoteActive(activity)
                }
            }
            PhoneWatchSync.shared.onRemoteWorkout = { remote in
                Task { @MainActor in
                    if let remote {
                        await applyRemoteWorkoutIfAvailable(remote)
                    } else {
                        if workout.applyRemoteEnd() {
                            fitnessSessionEvents.sessionDidComplete()
                        }
                    }
                }
            }
            // The watch changed a set — reload if we're showing that same session.
            PhoneWatchSync.shared.onRemoteSessionChanged = { sessionId in
                Task { @MainActor in
                    if workout.vm?.payload.sessionId == sessionId {
                        await workout.vm?.load()
                    }
                }
            }
            PhoneWatchSync.shared.onRemoteSessionSnapshot = { sessionId, detail in
                Task { @MainActor in
                    if workout.vm?.payload.sessionId == sessionId {
                        workout.vm?.applyRemoteSnapshot(detail)
                    }
                }
            }
            PhoneWatchSync.shared.onRemoteSessionCompleted = { _ in
                Task { @MainActor in
                    fitnessSessionEvents.sessionDidComplete()
                }
            }
            // Live heart rate from the watch → shown in the floating workout bar.
            PhoneWatchSync.shared.onRemoteHeartRate = { sessionId, bpm in
                Task { @MainActor in
                    if workout.vm?.payload.sessionId == sessionId {
                        workout.remoteHeartRate = bpm
                    }
                }
            }
            // Catch up: if the watch already started a workout before this app
            // launched, open it now (the callback above wasn't set when the
            // watch's state first arrived).
            PhoneWatchSync.shared.refreshFromContext()
            if let existing = PhoneWatchSync.shared.currentWorkout() {
                await applyRemoteWorkoutIfAvailable(existing)
            }
        }
    }

    @MainActor
    private func applyRemoteWorkoutIfAvailable(_ remote: WorkoutSyncPayload) async {
        do {
            let detail = try await FitnessAPIClient.sessionDetail(id: remote.sessionId)
            let fallbackName = remote.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = FitnessWorkoutSessionPayload(
                sessionId: remote.sessionId,
                name: detail.name.isEmpty ? fallbackName : detail.name
            )
            workout.applyRemoteStart(payload)
            workout.vm?.applyRemoteSnapshot(detail)
        } catch {
            if FitnessAPIClient.isMissingResourceError(error) {
                if workout.vm?.payload.sessionId == remote.sessionId,
                   workout.applyRemoteEnd() {
                    fitnessSessionEvents.sessionDidComplete()
                }
                PhoneWatchSync.shared.broadcastWorkout(nil)
            } else {
                workout.applyRemoteStart(FitnessWorkoutSessionPayload(sessionId: remote.sessionId, name: remote.name))
                await workout.vm?.load()
            }
        }
    }
}

/// Applies the tab-bar bottom accessory (the collapsed workout bar) only while a
/// workout is minimized. Applying `tabViewBottomAccessory` unconditionally would
/// leave an empty accessory bar visible even with no workout, so it's gated here.
private struct CollapsedWorkoutAccessory: ViewModifier {
    @ObservedObject var workout: ActiveWorkoutStore

    func body(content: Content) -> some View {
        if let vm = workout.vm, workout.isMinimized {
            content
                .tabViewBottomAccessory {
                    WorkoutAccessoryBar(vm: vm, workout: workout) { workout.restore() }
                }
        } else {
            content
        }
    }
}

/// Bar shown in the tab-bar accessory while a workout is collapsed. It mirrors the
/// in-workout mini player (state prefix, current exercise, time) via the shared
/// `miniPlayerState`. Tapping the info area re-opens the full screen; the trailing
/// button advances the workout (or expands to finish).
private struct WorkoutAccessoryBar: View {
    @ObservedObject var vm: FitnessActiveSessionViewModel
    @ObservedObject var workout: ActiveWorkoutStore
    let onExpand: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = vm.miniPlayerState(now: context.date)
            HStack(spacing: 10) {
                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(state.prefix)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(state.tint)
                                Text(state.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            Text(state.timeText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let bpm = workout.remoteHeartRate {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("\(bpm)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity)
                }

                Button {
                    Haptics.tap()
                    if state.isFinishAction {
                        onExpand()
                    } else {
                        Task { await vm.handleMiniPlayerAction() }
                    }
                } label: {
                    Circle()
                        .fill(state.actionFill)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
                        .overlay(
                            Image(systemName: state.actionSymbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(state.actionForeground)
                                .offset(x: state.actionSymbol == "play.fill" ? 1.5 : 0)
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.actionDisabled)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Slight gray tint so the white "开始" button stays visible on the bar.
            .background(Color(hex: "1C1C1E").opacity(0.07))
        }
    }
}

private struct RecordWorkspaceView: View {
    @StateObject private var calendarStore = TimeCalendarStore()
    @StateObject private var dashboardVM = TimeDashboardViewModel()
    @State private var selection = 0
    private let switcherHeight: CGFloat = 40
    private let switcherTopPadding: CGFloat = 0
    private let switcherBottomPadding: CGFloat = 8
    private var switcherContainerHeight: CGFloat {
        switcherHeight + switcherTopPadding + switcherBottomPadding
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ZStack {
                    switch selection {
                    case 1:
                        CalendarTrackerView2(store: calendarStore)
                    case 2:
                        TimeDashboardView(viewModel: dashboardVM)
                    default:
                        RecordView(calendarStore: calendarStore)
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: max(proxy.size.height - switcherContainerHeight, 0)
                )
                .offset(y: switcherContainerHeight)
                .transaction { transaction in
                    transaction.disablesAnimations = true
                }

                RecordWorkspaceSwitcher(selection: $selection)
                    .padding(.horizontal, 18)
                    .padding(.top, switcherTopPadding)
                    .padding(.bottom, switcherBottomPadding)
                    .frame(width: proxy.size.width)
                    .frame(height: switcherContainerHeight, alignment: .top)
                    .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea(.keyboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "F5F6F8").ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RecordWorkspaceSwitcher: View {
    @Binding var selection: Int
    private let height: CGFloat = 40
    private let buttonHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 4) {
            switchButton(title: "记录", symbol: "timer", tag: 0)
            switchButton(title: "日历", symbol: "calendar", tag: 1)
            switchButton(title: "报表", symbol: "chart.bar.fill", tag: 2)
        }
        .padding(4)
        .frame(height: height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(width: 300, height: height)
    }

    private func switchButton(title: String, symbol: String, tag: Int) -> some View {
        let isOn = selection == tag
        return Button {
            endEditingIfAvailable()
            selection = tag
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 15, height: 15)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isOn ? .white : Color(hex: "8A8F9C"))
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(isOn ? Color(hex: "FF7847") : .clear, in: Capsule())
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOn)
        }
        .buttonStyle(HapticButtonStyle())
    }
}

#if canImport(UIKit)
private func endEditingIfAvailable() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
#else
private func endEditingIfAvailable() {}
#endif

extension View {
    /// Lets the tab bar minimize on scroll even when a screen's content is shorter
    /// than the viewport. `.onScrollDown` only fires on an actual downward scroll
    /// gesture, which short pages can't produce; forcing bounce lets the drag
    /// register without padding the page with empty spacer views.
    func collapsibleTabScroll() -> some View {
        self
            .scrollBounceBehavior(.always, axes: .vertical)
            .tabBarMinimizeBehavior(.onScrollDown)
    }
}

private struct ProfileTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            List {
                if let user = session.session {
                    Section("账户") {
                        LabeledContent("昵称", value: user.nickname)
                        LabeledContent("用户 ID", value: String(user.userId))
                        if let unit = user.unitSystem, !unit.isEmpty {
                            LabeledContent("单位", value: unit)
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Haptics.tap()
                        session.logout()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}

struct HealthExportView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: HealthExportViewModel
    @ObservedObject private var observerSyncManager: HealthObserverSyncManager

    init(configurationStore: ConfigurationStore, observerSyncManager: HealthObserverSyncManager) {
        _viewModel = StateObject(wrappedValue: HealthExportViewModel(store: configurationStore))
        _observerSyncManager = ObservedObject(wrappedValue: observerSyncManager)
    }

    var body: some View {
        NavigationStack {
            Form {
                configurationSection
                endpointSection
                metricsSection
                sendSection
                previewSection
                shortcutsSection
                observerSection
            }
            .navigationTitle("Health Export")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        let config = viewModel.store.addConfiguration()
                        viewModel.select(config)
                    } label: {
                        Label("新增接口", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.reloadSelectedConfiguration()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.reloadSelectedConfiguration()
                }
            }
            .onChange(of: viewModel.selectedConfigurationID) { _, newValue in
                guard let newValue, let config = viewModel.store.configuration(id: newValue) else { return }
                viewModel.draft = config
            }
            .onChange(of: viewModel.draft) { _, newValue in
                viewModel.draftDidChange(newValue)
            }
        }
    }

    private var configurationSection: some View {
        Section("接口配置") {
            Picker("当前接口", selection: Binding(
                get: { viewModel.selectedConfigurationID ?? viewModel.draft.id },
                set: { viewModel.selectedConfigurationID = $0 }
            )) {
                ForEach(viewModel.store.configurations) { configuration in
                    Text(configuration.name).tag(configuration.id)
                }
            }

            TextField("配置名称", text: $viewModel.draft.name)
                .textInputAutocapitalization(.never)

            Stepper(value: $viewModel.draft.lookbackHours, in: 1...168) {
                LabeledContent("发送窗口", value: "\(viewModel.draft.lookbackHours) 小时")
            }

            Toggle("包含最近样本明细", isOn: $viewModel.draft.includeSamples)

            Button(role: .destructive) {
                Haptics.tap()
                let removed = viewModel.draft
                viewModel.store.delete(removed)
                viewModel.select(viewModel.store.configurations.first ?? viewModel.store.addConfiguration())
            } label: {
                Label("删除当前接口", systemImage: "trash")
            }
            .disabled(viewModel.store.configurations.count <= 1)
        }
    }

    private var endpointSection: some View {
        Section("接收地址") {
            TextField(AppEnvironment.defaultHealthIngestURL, text: $viewModel.draft.endpointURL, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Bearer Token，可选", text: $viewModel.draft.bearerToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var metricsSection: some View {
        Section("健康信息") {
            ForEach(MetricPriority.allCases) { priority in
                let metrics = HealthMetric.allCases.filter { $0.priority == priority }
                DisclosureGroup(priority.rawValue) {
                    ForEach(metrics) { metric in
                        Toggle(isOn: viewModel.metricBinding(metric)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.title)
                                    Text(metric.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: metric.symbolName)
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sendSection: some View {
        Section("发送") {
            Button {
                Haptics.tap()
                Task { await viewModel.generatePreview() }
            } label: {
                Label(viewModel.isGeneratingPreview ? "生成中" : "生成数据预览", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(viewModel.isGeneratingPreview || viewModel.isSending || !viewModel.draft.isReadyToPreview)

            Button {
                Haptics.tap()
                Task { await viewModel.sendNow() }
            } label: {
                Label(viewModel.isSending ? "发送中" : "发送当前预览", systemImage: "paperplane.fill")
            }
            .disabled(viewModel.isSending || viewModel.previewPayload == nil || !viewModel.draft.isReadyToSend)

            if let lastSentAt = viewModel.draft.lastSentAt {
                LabeledContent("上次发送", value: lastSentAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let lastStatus = viewModel.draft.lastStatus, !lastStatus.isEmpty {
                Text(lastStatus)
                    .font(.footnote)
                    .foregroundStyle(lastStatus.contains("成功") ? .green : .red)
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.previewPayload != nil && !viewModel.draft.isReadyToSend {
                Text("预览已生成。填写有效的 http/https 接口地址后才能发送。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var previewSection: some View {
        Section("数据预览") {
            if viewModel.previewJSON.isEmpty {
                Text("点击\u{201C}生成数据预览\u{201D}后，这里会显示本次将发送到接口的 JSON。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if !viewModel.previewSummary.isEmpty {
                    Text(viewModel.previewSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: .constant(viewModel.previewJSON))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    private var shortcutsSection: some View {
        Section("快捷指令") {
            Label("在快捷指令 App 中添加\u{201C}发送健康数据\u{201D}动作，然后选择这里保存的接口配置。", systemImage: "timer")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var observerSection: some View {
        Section("自动同步") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("启用 HealthKit Observer 自动上传", isOn: Binding(
                    get: { observerSyncManager.isEnabled },
                    set: { observerSyncManager.setEnabled($0) }
                ))

                HStack(spacing: 12) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("HealthKit Observer 已接入")
                            .font(.headline)
                        Text(observerSyncManager.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastSyncAt = observerSyncManager.lastSyncAt {
                    LabeledContent("最近一次自动上传", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("最近一次自动上传：暂无")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ObserverStepRow(index: 1, title: "Watch 记录心率", detail: "手表先写入 HealthKit。")
                    ObserverStepRow(index: 2, title: "同步到 iPhone", detail: "系统把变化送到手机。")
                    ObserverStepRow(index: 3, title: "Observer 被触发", detail: "HKObserverQuery 收到更新事件。")
                    ObserverStepRow(index: 4, title: "App 自动上传", detail: "直接推送到你的服务端。")
                }

                Text("延迟通常是几秒到几分钟。配置好接口后，健康数据更新会自动上传，不需要手动点发送。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Haptics.tap()
                    Task { await observerSyncManager.refreshObservers(force: true) }
                } label: {
                    Label("重新注册 Observer", systemImage: "arrow.clockwise")
                }

                if !observerSyncManager.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("运行日志")
                            .font(.subheadline.weight(.semibold))

                        ForEach(observerSyncManager.logs.prefix(5)) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.message)
                                    .font(.footnote)
                                Text("\(log.level.uppercased()) · \(log.createdAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}

private struct ObserverStepRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue, in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
