import SwiftUI

@MainActor
struct RecordView: View {
    @ObservedObject var calendarStore: TimeCalendarStore
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

            ScrollView {
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
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: 430)
            }
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
            try await ShortcutAPI.start(taskName: task.name, typeId: task.subtypeId)
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
private struct AddShortcutSheet: View {
    @ObservedObject var store: ShortcutRecordStore
    @ObservedObject var calendarStore: TimeCalendarStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedTemplate = ShortcutRecordStore.iconOptions.first ?? ShortcutRecordStore.defaultTasks[0]
    @State private var searchText = ""
    @State private var iconFilterTag: String = "common"
    @State private var pickedCategory: String
    @State private var pickedSubtype: String?
    @State private var showManagement = false
    @State private var managementTab: ManagementTab = .category
    @FocusState private var isNameFocused: Bool

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private static let iconFilterTags: [(id: String, label: String)] = [
        ("common", "常用"), ("work", "工作"), ("study", "学习"),
        ("life", "生活"), ("sport", "运动"), ("rest", "休息"),
        ("fun", "娱乐"), ("all", "全部"),
    ]

    private static let iconCategorySymbols: [String: [String]] = [
        "common": ["star.fill", "heart.fill", "clock.fill", "calendar", "bookmark.fill",
                   "flag.fill", "note.text", "camera.fill", "music.note", "moon.stars.fill",
                   "flame.fill", "leaf.fill"],
        "work":   ["briefcase.fill", "doc.fill", "envelope.fill", "phone.fill", "message.fill",
                   "printer.fill", "desktopcomputer", "iphone", "ipad.landscape", "calendar",
                   "clock.fill", "video.fill"],
        "study":  ["book.fill", "book.closed.fill", "note.text", "doc.fill",
                   "music.note", "mic.fill", "star.fill", "bookmark.fill"],
        "life":   ["house.fill", "fork.knife", "cup.and.saucer.fill", "mug.fill", "cart.fill",
                   "bag.fill", "car.fill", "umbrella.fill", "key.fill", "wallet.pass.fill",
                   "suitcase.fill", "gift.fill"],
        "sport":  ["figure.run", "figure.walk", "dumbbell.fill", "bicycle", "heart.circle.fill",
                   "figure.mind.and.body", "flame.fill", "mountain.2.fill"],
        "rest":   ["moon.stars.fill", "moon.fill", "sun.max.fill", "cloud.fill", "leaf.fill",
                   "figure.mind.and.body", "cup.and.saucer.fill", "drop.fill", "water.waves"],
        "fun":    ["gamecontroller.fill", "music.note", "video.fill", "mic.fill", "photo.fill",
                   "camera.fill", "heart.fill", "gift.fill", "map.fill", "airplane"],
    ]

    init(store: ShortcutRecordStore, calendarStore: TimeCalendarStore) {
        self.store = store
        self.calendarStore = calendarStore
        let first = calendarStore.categories.first
        _pickedCategory = State(initialValue: first?.id ?? "")
        _pickedSubtype = State(initialValue: first?.types.first?.id)
    }

    private var category: Calendar2Category {
        calendarStore.categories.first { $0.id == pickedCategory }
            ?? calendarStore.category(for: pickedCategory)
    }

    private var filteredOptions: [ShortcutTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = ShortcutRecordStore.iconOptions
        if !query.isEmpty {
            return Array(all.filter {
                $0.name.lowercased().contains(query) || $0.symbolName.lowercased().contains(query)
            }.prefix(60))
        }
        if iconFilterTag == "all" { return all }
        if let symbols = Self.iconCategorySymbols[iconFilterTag] {
            let filtered = all.filter { symbols.contains($0.symbolName) }
            if !filtered.isEmpty { return filtered }
        }
        return Array(all.prefix(12))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    nameField
                    iconSection
                    categorySection
                    subcategorySection
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
            Text("新增快捷指令")
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

    // MARK: - Icon Section

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("图标")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: "9A9AA2"))
                TextField("搜索图标（如：健身 / music / heart）", text: $searchText)
                    .font(.system(size: 14, weight: .regular))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(hex: "B0B0B8"))
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(hex: "F5F5F7"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
            )

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Self.iconFilterTags, id: \.id) { tag in
                            let isOn = iconFilterTag == tag.id
                            Button { iconFilterTag = tag.id } label: {
                                Text(tag.label)
                                    .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                                    .foregroundStyle(isOn ? .white : Color(hex: "4A4A54"))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(
                                        isOn ? Calendar2Style.accent : Color(hex: "F0F0F5"),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(PressButtonStyle())
                            .animation(.easeOut(duration: 0.15), value: iconFilterTag)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: selectedTemplate.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Calendar2Style.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("已选图标")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "B0B0B8"))
                    Text(selectedTemplate.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "4A4A54"))
                }
                Spacer()
            }

            LazyVGrid(columns: iconColumns, spacing: 8) {
                ForEach(filteredOptions) { template in
                    let isOn = selectedTemplate.symbolName == template.symbolName
                    Button { selectedTemplate = template } label: {
                        Image(systemName: template.symbolName)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(isOn ? .white : Design.icon)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                isOn ? Calendar2Style.accent : Color(hex: "F5F5F7"),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isOn ? Calendar2Style.accent : Color(hex: "ECECEF"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredOptions.isEmpty {
                Text("没找到匹配的图标，换个关键词试试")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "9A9AA2"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
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
                Text("保存指令")
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
        store.addTask(name: trimmedName, template: selectedTemplate, categoryId: pickedCategory.isEmpty ? nil : pickedCategory, subtypeId: pickedSubtype)
        dismiss()
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
