import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordWorkspaceView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet.rectangle.portrait.fill")
                }

            HealthExportView()
                .tabItem {
                    Label("数据", systemImage: "house")
                }

            PlaceholderTabView(title: "我的", symbolName: "person")
                .tabItem {
                    Label("我的", systemImage: "person")
                }
        }
        .tint(Color(hex: "FF7847"))
    }
}

private struct RecordWorkspaceView: View {
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            RecordWorkspaceSwitcher(selection: $selection)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)

            ZStack {
                switch selection {
                case 1:
                    CalendarTrackerView2()
                default:
                    RecordView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "F5F6F8").ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RecordWorkspaceSwitcher: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            switchButton(title: "记录", symbol: "timer", tag: 0)
            switchButton(title: "日历", symbol: "calendar", tag: 1)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: 220)
    }

    private func switchButton(title: String, symbol: String, tag: Int) -> some View {
        let isOn = selection == tag
        return Button {
            endEditingIfAvailable()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = tag
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isOn ? .white : Color(hex: "8A8F9C"))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isOn ? Color(hex: "FF7847") : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
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
    @StateObject private var store = ConfigurationStore()
    @StateObject private var observerSyncManager = HealthObserverSyncManager.shared
    @State private var selectedConfigurationID: UUID?
    @State private var draft = ExportConfiguration()
    @State private var isSending = false
    @State private var isGeneratingPreview = false
    @State private var statusMessage = ""
    @State private var previewPayload: HealthExportPayload?
    @State private var previewSummary = ""
    @State private var previewJSON = ""

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
                        let config = store.addConfiguration()
                        select(config)
                    } label: {
                        Label("新增接口", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                reloadSelectedConfiguration()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    reloadSelectedConfiguration()
                }
            }
            .onChange(of: selectedConfigurationID) { _, newValue in
                guard let newValue, let config = store.configuration(id: newValue) else { return }
                draft = config
            }
            .onChange(of: draft) { _, newValue in
                store.update(newValue)
                clearPreview()
            }
        }
    }

    private var configurationSection: some View {
        Section("接口配置") {
            Picker("当前接口", selection: Binding(
                get: { selectedConfigurationID ?? draft.id },
                set: { selectedConfigurationID = $0 }
            )) {
                ForEach(store.configurations) { configuration in
                    Text(configuration.name).tag(configuration.id)
                }
            }

            TextField("配置名称", text: $draft.name)
                .textInputAutocapitalization(.never)

            Stepper(value: $draft.lookbackHours, in: 1...168) {
                LabeledContent("发送窗口", value: "\(draft.lookbackHours) 小时")
            }

            Toggle("包含最近样本明细", isOn: $draft.includeSamples)

            Button(role: .destructive) {
                let removed = draft
                store.delete(removed)
                select(store.configurations.first ?? store.addConfiguration())
            } label: {
                Label("删除当前接口", systemImage: "trash")
            }
            .disabled(store.configurations.count <= 1)
        }
    }

    private var endpointSection: some View {
        Section("接收地址") {
            TextField("https://example.com/api/health/daily-sync", text: $draft.endpointURL, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Bearer Token，可选", text: $draft.bearerToken)
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
                        Toggle(isOn: metricBinding(metric)) {
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
                Task { await generatePreview() }
            } label: {
                Label(isGeneratingPreview ? "生成中" : "生成数据预览", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(isGeneratingPreview || isSending || !draft.isReadyToPreview)

            Button {
                Task { await sendNow() }
            } label: {
                Label(isSending ? "发送中" : "发送当前预览", systemImage: "paperplane.fill")
            }
            .disabled(isSending || previewPayload == nil || !draft.isReadyToSend)

            if let lastSentAt = draft.lastSentAt {
                LabeledContent("上次发送", value: lastSentAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let lastStatus = draft.lastStatus, !lastStatus.isEmpty {
                Text(lastStatus)
                    .font(.footnote)
                    .foregroundStyle(lastStatus.contains("成功") ? .green : .red)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if previewPayload != nil && !draft.isReadyToSend {
                Text("预览已生成。填写有效的 http/https 接口地址后才能发送。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var previewSection: some View {
        Section("数据预览") {
            if previewJSON.isEmpty {
                Text("点击“生成数据预览”后，这里会显示本次将发送到接口的 JSON。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if !previewSummary.isEmpty {
                    Text(previewSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: .constant(previewJSON))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    private var shortcutsSection: some View {
        Section("快捷指令") {
            Label("在快捷指令 App 中添加“发送健康数据”动作，然后选择这里保存的接口配置。", systemImage: "timer")
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

    private func select(_ configuration: ExportConfiguration) {
        selectedConfigurationID = configuration.id
        draft = configuration
    }

    private func reloadSelectedConfiguration() {
        store.load()
        if let selectedConfigurationID,
           let selected = store.configuration(id: selectedConfigurationID) {
            draft = selected
        } else {
            select(store.configurations.first ?? store.addConfiguration())
        }
    }

    private func metricBinding(_ metric: HealthMetric) -> Binding<Bool> {
        Binding {
            draft.selectedMetricIDs.contains(metric.id)
        } set: { isEnabled in
            if isEnabled {
                draft.selectedMetricIDs.insert(metric.id)
            } else {
                draft.selectedMetricIDs.remove(metric.id)
            }
        }
    }

    private func clearPreview() {
        previewPayload = nil
        previewSummary = ""
        previewJSON = ""
    }

    private func generatePreview() async {
        isGeneratingPreview = true
        statusMessage = ""
        do {
            let exporter = HealthKitExporter()
            statusMessage = "正在请求 HealthKit 权限并生成 JSON..."
            try await exporter.requestAuthorization(for: draft)
            let payload = try await exporter.buildPayload(for: draft)
            let data = try payload.jsonData
            guard let json = String(data: data, encoding: .utf8), !json.isEmpty else {
                throw ExportError.invalidPreview
            }
            previewPayload = payload
            previewSummary = previewSummaryText(for: payload)
            previewJSON = json
            statusMessage = "预览已生成，确认无误后再发送。"
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = message
        }
        isGeneratingPreview = false
    }

    private func sendNow() async {
        guard let previewPayload else {
            statusMessage = "请先生成数据预览。"
            return
        }

        isSending = true
        statusMessage = ""
        do {
            let result = try await HealthKitExporter().send(payload: previewPayload)
            store.markSent(id: draft.id, status: result)
            if let updated = store.configuration(id: draft.id) {
                draft = updated
            }
            statusMessage = result
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.markSent(id: draft.id, status: message)
            if let updated = store.configuration(id: draft.id) {
                draft = updated
            }
            statusMessage = message
        }
        isSending = false
    }

    private func previewSummaryText(for payload: HealthExportPayload) -> String {
        if payload.itemCount == 0 {
            return "预览类型：健康指标，0 条 metrics。当前发送窗口内没有可发送指标。"
        }
        return "预览类型：健康指标，\(payload.itemCount) 条 metrics。"
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
