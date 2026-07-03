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

    func start(_ payload: FitnessWorkoutSessionPayload) {
        vm = FitnessActiveSessionViewModel(payload: payload)
        isMinimized = false
    }
    func minimize() { isMinimized = true }
    func restore() { isMinimized = false }
    func end() {
        vm = nil
        isMinimized = false
    }
}

extension Notification.Name {
    /// Posted when a workout session finishes (completed or discarded) so screens
    /// can refresh their records without a direct reference to the session view.
    static let fitnessSessionDidComplete = Notification.Name("fitnessSessionDidComplete")
}

struct ContentView: View {
    @StateObject private var workout = ActiveWorkoutStore()
    // Persist the selected tab so collapsing the workout (which toggles the tab-bar
    // accessory) keeps the user on the tab they were on, not resetting to 记录.
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordWorkspaceView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(0)

            FitnessTemplateListView()
                .tabItem {
                    Label("健身", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(1)

            HealthExportView()
                .tabItem {
                    Label("数据", systemImage: "house")
                }
                .tag(2)

            PlaceholderTabView(title: "我的", symbolName: "person")
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(3)
        }
        .tint(Color(hex: "FF7847"))
        .environmentObject(workout)
        // Attach the collapsed-workout accessory to the tab bar ONLY while a workout
        // is minimized — otherwise the accessory chrome would show as an empty bar.
        // Applied as a conditional modifier on the same TabView so tab state is kept.
        .modifier(CollapsedWorkoutAccessory(workout: workout))
        // The full-screen workout is hosted above the tabs; re-opening reuses the
        // stored view-model, so no reload happens when expanding from the accessory.
        .overlay {
            if let vm = workout.vm, !workout.isMinimized {
                FitnessActiveSessionView(vm: vm) {
                    NotificationCenter.default.post(name: .fitnessSessionDidComplete, object: nil)
                }
                .environmentObject(workout)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: workout.isMinimized)
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: workout.vm == nil)
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
                    WorkoutAccessoryBar(vm: vm) { workout.restore() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
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

private struct PlaceholderTabView: View {
    let title: String
    let symbolName: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbolName)
        }
    }
}

struct HealthExportView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = HealthExportViewModel()
    @ObservedObject private var observerSyncManager = HealthObserverSyncManager.shared

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
            TextField("http://100.67.64.11:8081/api/health/ingest", text: $viewModel.draft.endpointURL, axis: .vertical)
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
