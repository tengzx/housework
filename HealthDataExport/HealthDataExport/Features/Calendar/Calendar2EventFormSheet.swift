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

    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String
    @State private var autoFilledName: String
    @State private var pickedCategory: String
    @State private var pickedType: String?
    @State private var pickedDayOffset: Int
    @State private var start: Int
    @State private var end: Int
    @State private var draftNote: String
    @State private var isSaving = false
    @State private var showManagement = false
    @State private var managementTab: ManagementTab = .category

    init(
        mode: Mode,
        store: TimeCalendarStore,
        onSave: @escaping (Calendar2Event) -> Void,
        onDelete: ((String) -> Void)?
    ) {
        self.mode = mode
        self.store = store
        self.onSave = onSave
        self.onDelete = onDelete

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
    private var canSave: Bool { !trimmedName.isEmpty && end > start && !isSaving }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    nameField
                    timeCard
                    categorySection
                    subcategorySection
                    noteField
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            saveBar
        }
        .background(Calendar2Style.sheet)
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

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.color)
                .frame(width: 13, height: 13)
            Text(isEdit ? "编辑记录" : "新建记录")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "23232A"))
            Spacer()
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

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("名称")
            TextField("输入事件名称", text: $draftName)
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
                    sectionLabel("时长")
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
                sectionLabel("分类")
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

    // MARK: - Note Field

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("备注")
            TextField("添加备注（可选）", text: $draftNote, axis: .vertical)
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
                Text("保存")
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

    private func commit() {
        guard canSave else { return }
        isSaving = true
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
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
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
