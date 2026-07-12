import SwiftUI

struct Calendar2EventFormSheet: View {
    enum Mode {
        case edit(Calendar2Event)
        case create(Calendar2Event)
    }

    let mode: Mode
    @ObservedObject var store: TimeCalendarStore
    let onSave: (Calendar2Event) -> Void
    let onDelete: ((String) -> Void)?
    let onShowDetails: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String
    @State private var autoFilledName: String
    @State private var pickedCategory: String
    @State private var pickedType: String?
    @State private var pickedDayOffset: Int
    @State private var start: Int
    @State private var end: Int
    @State private var draftNote: String
    @State private var quickText: String
    @State private var quickError: String
    @State private var showDetails: Bool
    @State private var isSaving = false
    @State private var didAddShortcut = false
    @State private var shortcutAlert: String?
    @State private var showManagement = false
    @State private var managementTab: ManagementTab = .category
    /// 归属目标/项目；nil = 公共。初始取事件上已保存的 goalId。
    @State private var pickedGoalId: Int?
    @State private var availableGoals: [RemoteGoal] = []
    @FocusState private var isQuickEntryFocused: Bool

    private let quickExamples = [
        L10n.tr("calendar.event_form.quick_example.1"),
        L10n.tr("calendar.event_form.quick_example.2"),
        L10n.tr("calendar.event_form.quick_example.3"),
    ]

    init(
        mode: Mode,
        store: TimeCalendarStore,
        onSave: @escaping (Calendar2Event) -> Void,
        onDelete: ((String) -> Void)?,
        onShowDetails: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.store = store
        self.onSave = onSave
        self.onDelete = onDelete
        self.onShowDetails = onShowDetails

        let source: Calendar2Event
        switch mode {
        case .edit(let e), .create(let e): source = e
        }
        _draftName = State(initialValue: source.name)
        switch mode {
        case .create: _autoFilledName = State(initialValue: source.name)
        case .edit:   _autoFilledName = State(initialValue: "")
        }
        _pickedCategory = State(initialValue: source.category)
        _pickedType = State(initialValue: source.typeId)
        _pickedDayOffset = State(initialValue: source.dayOffset)
        _start = State(initialValue: source.start)
        _end = State(initialValue: source.end)
        _draftNote = State(initialValue: source.note ?? "")
        _pickedGoalId = State(initialValue: source.goalId)
        _quickText = State(initialValue: "")
        _quickError = State(initialValue: "")
        _showDetails = State(initialValue: {
            if case .edit = mode { return true }
            return false
        }())
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var originalEvent: Calendar2Event? {
        if case .edit(let e) = mode { return e }
        return nil
    }

    private var category: Calendar2Category {
        store.categories.first { $0.id == pickedCategory } ?? store.category(for: pickedCategory)
    }

    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedQuickText: String { quickText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isQuickCreate: Bool { !isEdit && !showDetails }
    private var canSave: Bool {
        if isSaving { return false }
        if isQuickCreate { return !trimmedQuickText.isEmpty }
        return !trimmedName.isEmpty && end > start
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isQuickCreate {
                        quickHeader
                    } else {
                        header
                    }
                    if isQuickCreate {
                        quickEntryField
                    } else {
                        nameField
                        timeCard
                        categorySection
                        subcategorySection
                        goalSection
                        noteField
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            saveBar
        }
        .background(Calendar2Style.sheet)
        .alert(L10n.tr("calendar.event_form.shortcut.title"), isPresented: Binding(
            get: { shortcutAlert != nil },
            set: { if !$0 { shortcutAlert = nil } }
        )) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(shortcutAlert ?? "")
        }
        .onAppear {
            guard isQuickCreate else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isQuickEntryFocused = true
            }
        }
        .task {
            availableGoals = (try? await GoalAPI.list()) ?? []
        }
        .sheet(isPresented: $showManagement) {
            Calendar2ManagementSheet(
                initialTab: managementTab,
                store: store,
                onDone: {
                    let cats = store.categories
                    if !cats.contains(where: { $0.id == pickedCategory }) {
                        pickedCategory = cats.first?.id ?? pickedCategory
                        pickedType = cats.first?.types.first?.id
                    } else if cats.first(where: { $0.id == pickedCategory })?.types.contains(where: { $0.id == pickedType }) == false {
                        pickedType = cats.first(where: { $0.id == pickedCategory })?.types.first?.id
                    }
                }
            )
        }
    }

    // MARK: - Header

    private var quickHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr("calendar.event_form.quick_header"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "111115"))
            Spacer()
            Button {
                openDetails()
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.tr("calendar.event_form.details"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Calendar2Style.muted)
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
            .buttonStyle(HapticButtonStyle())
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.color)
                .frame(width: 13, height: 13)
            Text(isEdit ? L10n.tr("calendar.event_form.title.edit") : L10n.tr("calendar.event_form.title.create"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "23232A"))
            Spacer()
            if isEdit {
                Button {
                    addAsShortcut()
                } label: {
                    Image(systemName: didAddShortcut ? "checkmark" : "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(didAddShortcut ? Color(hex: "24C48E") : Calendar2Style.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            (didAddShortcut ? Color(hex: "24C48E") : Calendar2Style.accent).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(Calendar2PressStyle())
                .disabled(didAddShortcut || trimmedName.isEmpty)
            }
            if isEdit, let onDelete, let event = originalEvent {
                Button(role: .destructive) {
                    onDelete(event.id)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(hex: "E5564B"))
                        .frame(width: 38, height: 38)
                        .background(Color(hex: "FCEBE9"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(Calendar2PressStyle())
            }
        }
    }

    /// Add the event being edited to the quick-record shortcut list, mirroring
    /// the current form state (name / category / subtype). The color follows the
    /// event's color when known so the shortcut reads the same on the record grid.
    private func addAsShortcut() {
        guard !trimmedName.isEmpty else { return }
        // Guard against duplicates client-side: the backend rejects a repeated
        // name ("shortcut name already exists"), so surface that up front instead
        // of enqueuing a create that can never land.
        if ShortcutRecordStore.shared.tasks.contains(where: { $0.name == trimmedName }) {
            shortcutAlert = L10n.tr("calendar.event_form.shortcut.duplicate", trimmedName)
            return
        }
        let colorHex = RemoteShortcut.normalizeHex(originalEvent?.colorHex) ?? ShortcutTask.defaultColorHex
        let template = ShortcutTask(
            name: trimmedName,
            symbolName: ShortcutRecordStore.symbolName(for: trimmedName),
            colorHex: colorHex
        )
        ShortcutRecordStore.shared.addTask(
            name: trimmedName,
            template: template,
            categoryId: pickedCategory.isEmpty ? nil : pickedCategory,
            subtypeId: pickedType
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didAddShortcut = true
        }
        shortcutAlert = L10n.tr("calendar.event_form.shortcut.added", trimmedName)
    }

    // MARK: - Quick Entry

    private var quickEntryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.tr("calendar.event_form.quick_input_placeholder"), text: $quickText, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isQuickEntryFocused)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(hex: "23232A"))
                .tint(Calendar2Style.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(quickExamples, id: \.self) { example in
                    Button {
                        quickText = example
                        isQuickEntryFocused = true
                    } label: {
                        Text(L10n.tr("calendar.event_form.quick_example_prefix", example))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "B8B8C0"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(HapticButtonStyle())
                }
            }
            .padding(.top, 2)

            if !quickError.isEmpty {
                Text(quickError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "E5564B"))
                    .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(L10n.tr("common.name"))
            TextField(L10n.tr("calendar.event_form.name_placeholder"), text: $draftName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "23232A"))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Time Card

    private var timeCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(L10n.tr("calendar.event_form.duration"))
                    Text(Calendar2Format.duration(max(end - start, 0)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Calendar2Style.accent)
                }
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color(hex: "D7D7DC"))
                    .padding(.bottom, 2)
            }

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.vertical, 14)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "8A8A92"))
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                Spacer()
                DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "B0B0B8"))
                DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
        .padding(18)
        .background(Color(hex: "F6F6F8"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionLabel(L10n.tr("record.shortcut.section.category"))
                Spacer()
                manageButton(tab: .category)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(store.categories) { item in
                    let isOn = pickedCategory == item.id
                    Button {
                        guard pickedCategory != item.id else { return }
                        pickedCategory = item.id
                        pickedType = item.types.first?.id
                        let suggested = item.types.first?.label ?? item.label
                        if draftName == autoFilledName {
                            draftName = suggested
                            autoFilledName = suggested
                        }
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
                sectionLabel(L10n.tr("record.shortcut.section.subcategory", category.label))
                Spacer()
                manageButton(tab: .subcategory)
            }
            let types = category.types
            if types.isEmpty {
                Text(L10n.tr("record.shortcut.empty_subcategory"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "B5B5BC"))
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(types) { type in
                        let isOn = pickedType == type.id
                        let tint = category.color
                        Button {
                            pickedType = type.id
                            if draftName == autoFilledName {
                                draftName = type.label
                                autoFilledName = type.label
                            }
                        } label: {
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

    // MARK: - Goal Section

    /// 归属目标/项目：公共（无归属）或某个 active 目标。事件原本挂在已归档
    /// 目标上时，所有 chip 都不高亮——不动它就保持原归属，选了才覆盖。
    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel(L10n.tr("calendar.event_form.goal_section"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                goalChip(id: nil, title: L10n.tr("record.intentions.group_public"), symbol: "tray")
                ForEach(availableGoals) { goal in
                    goalChip(id: goal.id, title: goal.name, symbol: goal.isProject ? "folder.fill" : "target")
                }
            }
        }
    }

    private func goalChip(id: Int?, title: String, symbol: String) -> some View {
        let isOn = pickedGoalId == id
        return Button {
            pickedGoalId = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Calendar2Style.accent : Color(hex: "9A9AA2"))
                Text(title)
                    .font(.system(size: 15, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Color(hex: "2A2A30") : Color(hex: "4A4A52"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .padding(.horizontal, 14)
            .background(
                isOn ? Calendar2Style.accent.opacity(0.11) : Color(hex: "F5F5F7"),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isOn ? Calendar2Style.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(Calendar2PressStyle())
    }

    // MARK: - Note Field

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(L10n.tr("intent.start_app_session.parameter.note.title"))
            TextField(L10n.tr("calendar.event_form.note_placeholder"), text: $draftNote, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "23232A"))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(hex: "ECECEF"), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
            Button { commit() } label: {
                Text(isQuickCreate ? L10n.tr("calendar.event_form.continue") : L10n.tr("common.save"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        canSave ? Calendar2Style.accent : Calendar2Style.faint,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: canSave ? Calendar2Style.accent.opacity(0.35) : .clear, radius: 10, x: 0, y: 5)
            }
            .buttonStyle(Calendar2PressStyle())
            .disabled(!canSave)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(Calendar2Style.sheet)
    }

    // MARK: - Helpers

    private func manageButton(tab: ManagementTab) -> some View {
        Button {
            managementTab = tab
            showManagement = true
        } label: {
            HStack(spacing: 3) {
                Text(L10n.tr("record.action.manage"))
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

    private func openDetails() {
        isQuickEntryFocused = false
        onShowDetails?()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showDetails = true
            }
        }
    }

    private func commit() {
        guard canSave else { return }
        isSaving = true
        if isQuickCreate {
            let text = trimmedQuickText
            let dayOffset = pickedDayOffset
            quickError = ""
            Task {
                if await store.createNaturalLanguageEvent(text: text, dayOffset: dayOffset) != nil {
                    dismiss()
                } else {
                    quickError = store.statusMessage
                }
                isSaving = false
            }
            return
        }

        let original = originalEvent
        let event = Calendar2Event(
            id: original?.id ?? "",
            sourceEventId: original?.sourceEventId,
            absoluteStartedAt: nil,
            absoluteEndedAt: nil,
            dayOffset: pickedDayOffset,
            start: start,
            end: end,
            name: trimmedName,
            category: pickedCategory,
            typeId: pickedType,
            source: original?.source ?? "manual",
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            goalId: pickedGoalId
        )
        onSave(event)
        dismiss()
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Calendar2Format.day(offset: pickedDayOffset) },
            set: { pickedDayOffset = Calendar2Format.dayOffset(for: $0) }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Calendar2Format.date(fromMinute: start) },
            set: { newValue in
                start = Calendar2Format.minute(fromDate: newValue)
                if end <= start { end = min(start + 5, Calendar2Layout.dayEnd * 60) }
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Calendar2Format.date(fromMinute: end) },
            set: { end = max(Calendar2Format.minute(fromDate: $0), start + 5) }
        )
    }
}
