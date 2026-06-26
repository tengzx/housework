import SwiftUI

@MainActor
struct RecordView: View {
    @StateObject private var store = ShortcutRecordStore()
    @State private var text = ""
    @State private var isAdding = false
    @State private var isManagingShortcuts = false
    @State private var isSendingStart = false
    @State private var isSendingStop = false
    @State private var statusMessage = ""
    @FocusState private var isInputFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Design.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 18)

                activeCard
                    .padding(.bottom, 18)

                inputBar
                    .padding(.bottom, 18)

                sectionHeader
                    .padding(.bottom, 12)

                shortcutsGrid

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusMessage.contains("失败") ? .red : Design.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: 430)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }

            if isAdding {
                AddShortcutOverlay(
                    store: store,
                    isPresented: $isAdding
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.18), value: isAdding)
        .task {
            await refreshRunningSession()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FLOW")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(Design.text)

            Spacer()

            Text(Self.todayText)
                .font(.system(size: 13, weight: .regular))
                .tracking(0.5)
                .foregroundStyle(Design.muted)
        }
    }

    private var activeCard: some View {
        Group {
            if let session = store.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
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
                        .padding(.bottom, 10)

                        Text(session.task.name)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Design.text)
                            .padding(.bottom, 4)

                        Text(timerText(from: session.startedAt, now: timeline.date))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .tracking(1)
                            .foregroundStyle(Design.accent)
                            .padding(.bottom, 14)

                        Button {
                            Task { await stopActiveSession() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSendingStop ? "hourglass" : "square.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("结束")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Design.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressButtonStyle())
                        .disabled(isSendingStop)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(activeCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(hex: "FFD9C7"), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
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
                .background(Design.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Design.line, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
            }
        }
    }

    private var activeCardBackground: some ShapeStyle {
        LinearGradient(
            colors: [Design.accentSoft, Design.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(store.activeSession == nil ? "现在在做什么…" : "切换到新的事…", text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Design.text)
                .textInputAutocapitalization(.never)
                .focused($isInputFocused)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Design.line, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 24, y: 8)
                .onSubmit {
                    submitText()
                }

            Button {
                submitText()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Design.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressButtonStyle())
            .disabled(trimmedText.isEmpty || isSendingStart)
            .opacity(trimmedText.isEmpty ? 0.4 : 1)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("快捷指令")
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
        HStack(spacing: 12) {
            Image(systemName: task.symbolName)
                .font(.system(size: 20, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? .white : Design.icon)
                .frame(width: 40, height: 40)
                .background(isOn ? Design.accent : Design.iconSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Design.accent : Design.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(isManagingShortcuts ? "管理中" : (isOn ? "进行中" : "按钮开始"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(isManagingShortcuts ? .red.opacity(0.72) : (isOn ? Design.accent : Design.muted.opacity(0.82)))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isManagingShortcuts {
                Button {
                    isInputFocused = false
                    Task { await deleteTask(task) }
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
                    Task { await startTask(task) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Design.accent, in: Circle())
                }
                .buttonStyle(PressButtonStyle())
                .disabled(isSendingStart)
                .opacity(isSendingStart ? 0.5 : 1)
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

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitText() {
        let name = trimmedText
        guard !name.isEmpty else { return }
        text = ""
        isInputFocused = false
        let task = ShortcutTask(name: name, symbolName: "pencil", colorHex: Design.accentHex)
        Task { await startTask(task) }
    }

    private func startTask(_ task: ShortcutTask) async {
        let hadActiveSession = store.activeSession != nil
        isSendingStart = true
        statusMessage = ""
        if hadActiveSession {
            store.stop(note: "")
        }
        store.start(task)

        do {
            if hadActiveSession {
                try await ShortcutAPI.end(note: "")
            }
            try await ShortcutAPI.start(taskName: task.name)
        } catch {
            statusMessage = "\(task.name) 同步失败：\(error.localizedDescription)"
        }
        isSendingStart = false
    }

    private func deleteTask(_ task: ShortcutTask) async {
        let isActiveTask = store.activeSession?.task.id == task.id
        store.removeTask(task)
        if isActiveTask {
            try? await ShortcutAPI.end(note: "")
        }
        if store.tasks.isEmpty {
            isManagingShortcuts = false
        }
    }

    private func stopActiveSession() async {
        isInputFocused = false
        isSendingStop = true
        statusMessage = ""
        store.stop(note: "")

        do {
            try await ShortcutAPI.end(note: "")
        } catch {
            statusMessage = "结束同步失败：\(error.localizedDescription)"
        }
        isSendingStop = false
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

@MainActor
private struct AddShortcutOverlay: View {
    @ObservedObject var store: ShortcutRecordStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedTemplate = ShortcutRecordStore.creationTemplates.first ?? ShortcutRecordStore.defaultTasks[0]
    @State private var searchText = ""
    @FocusState private var isNameFocused: Bool

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private var filteredOptions: [ShortcutTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let options = ShortcutRecordStore.iconOptions
        if query.isEmpty {
            return Array(options.prefix(36))
        }
        return Array(options.filter {
            $0.name.lowercased().contains(query) || $0.symbolName.lowercased().contains(query)
        }.prefix(60))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Design.line)
                    .frame(width: 40, height: 4)
                    .padding(.bottom, 18)

                HStack {
                    Text("新增快捷指令")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Design.text)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Design.muted)
                            .frame(width: 34, height: 34)
                            .background(Design.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressButtonStyle())
                }
                .padding(.bottom, 20)

                fieldLabel("名称")
                TextField("例如：写日记", text: $name)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Design.text)
                    .textInputAutocapitalization(.never)
                    .focused($isNameFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Design.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Design.line, lineWidth: 1)
                    )
                    .padding(.bottom, 20)

                fieldLabel("图标")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Design.muted)

                    TextField("搜索图标（英文，如 music / heart / book）", text: $searchText)
                        .font(.system(size: 14, weight: .regular))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Design.muted)
                                .padding(4)
                        }
                        .buttonStyle(PressButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Design.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Design.line, lineWidth: 1)
                )
                .padding(.bottom, 12)

                HStack(spacing: 10) {
                    Image(systemName: selectedTemplate.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Design.accent)
                        .frame(width: 24, height: 24)

                    Text(selectedTemplate.symbolName)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Design.muted)

                    Spacer()
                }
                .padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: iconColumns, spacing: 8) {
                        ForEach(filteredOptions) { template in
                            let isOn = selectedTemplate.symbolName == template.symbolName
                            Button {
                                selectedTemplate = template
                            } label: {
                                Image(systemName: template.symbolName)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(isOn ? .white : Design.icon)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(isOn ? Design.accent : Design.iconSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isOn ? Design.accent : Design.iconLine, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PressButtonStyle())
                        }
                    }

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && filteredOptions.isEmpty {
                        Text("没找到匹配的图标，换个英文关键词试试")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Design.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .frame(minHeight: 120)
                .padding(.bottom, 16)

                Button {
                    save()
                } label: {
                    Text("保存指令")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Design.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressButtonStyle())
                .disabled(trimmedName.isEmpty)
                .opacity(trimmedName.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 430)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.88)
            .background(Design.surface)
            .clipShape(TopRoundedRectangle(radius: 24))
            .overlay(alignment: .top) {
                TopRoundedRectangle(radius: 24)
                    .stroke(Design.line, lineWidth: 1)
            }
            .transition(.move(edge: .bottom))
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Design.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.addTask(name: trimmedName, template: selectedTemplate)
        isPresented = false
    }
}

private struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
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
    static let line = Color(hex: "E4E6EB")
    static let text = Color(hex: "1A1C20")
    static let muted = Color(hex: "8A8F9C")
    static let icon = Color(hex: "6F7480")
    static let iconSurface = Color(hex: "F7F8FA")
    static let iconLine = Color(hex: "EEF0F3")
    static let accentHex = "FF7847"
    static let accent = Color(hex: accentHex)
    static let accentSoft = Color(hex: "FFF7F3")
    static let green = Color(hex: "22C55E")
}
