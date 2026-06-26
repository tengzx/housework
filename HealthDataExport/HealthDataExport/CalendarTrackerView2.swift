import SwiftUI

struct CalendarTrackerView2: View {
    @StateObject private var store = TimeCalendarStore()
    @State private var anchorOffset = -2
    @State private var dragX: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var isSettlingDrag = false
    @State private var timelineWidth: CGFloat = 0
    @State private var selectedEvent: Calendar2Event?
    @State private var draftEvent: Calendar2Event?

    private var visibleOffsets: [Int] {
        [anchorOffset, anchorOffset + 1, anchorOffset + 2]
    }

    private var trackOffsets: [Int] {
        [-1, 0, 1, 2, 3].map { anchorOffset + $0 }
    }

    private var monthText: String {
        Calendar2Format.month(Calendar2Format.day(offset: anchorOffset))
    }

    private var pagingColumnWidth: CGFloat {
        max(Calendar2Layout.estimatedColumnWidth, timelineWidth / 3)
    }

    var body: some View {
        ZStack {
            Calendar2Style.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                dayHeader
                timeline
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .simultaneousGesture(horizontalHistoryDrag)
        }
        .sheet(item: $selectedEvent) { event in
            Calendar2EventFormSheet(
                mode: .edit(event),
                categories: store.categories,
                categoryProvider: store.category(for:),
                onSave: saveEditedEvent,
                onDelete: deleteEvent
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Calendar2Style.sheet)
        }
        .sheet(item: $draftEvent) { draft in
            Calendar2EventFormSheet(
                mode: .create(draft),
                categories: store.categories,
                categoryProvider: store.category(for:),
                onSave: createEvent,
                onDelete: nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Calendar2Style.sheet)
        }
        .task {
            await store.loadVisibleRange(offsets: trackOffsets)
        }
        .refreshable {
            await store.refresh(offsets: trackOffsets)
        }
        .onChange(of: anchorOffset) { _, _ in
            Task {
                await store.loadVisibleRange(offsets: trackOffsets)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(monthText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Calendar2Style.text)

                Text(historyHint)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Calendar2Style.muted)
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                draftEvent = store.makeDraftEvent(dayOffset: min(0, anchorOffset + 2))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Calendar2Style.accent)
                    .padding(4)
            }
            .buttonStyle(.plain)

            if anchorOffset != -2 {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        anchorOffset = -2
                    }
                } label: {
                    Text("今天")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Calendar2Style.accent)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var historyHint: String {
        if !store.statusMessage.isEmpty {
            return store.statusMessage
        }
        return anchorOffset == -2 ? "左右滑动查看历史" : "正在查看 \(Calendar2Format.shortRange(visibleOffsets))"
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Calendar2Layout.gutter)

            GeometryReader { geo in
                let columnWidth = geo.size.width / 3

                HStack(spacing: 0) {
                    ForEach(trackOffsets, id: \.self) { offset in
                        dayHeaderCell(offset: offset)
                            .frame(width: columnWidth)
                    }
                }
                .offset(x: -columnWidth + dragX)
                .animation(isHorizontalDrag ? nil : .spring(response: 0.3, dampingFraction: 0.88), value: anchorOffset)
                .onAppear {
                    timelineWidth = geo.size.width
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    timelineWidth = newWidth
                }
            }
            .clipped()
        }
        .padding(.bottom, 8)
        .padding(.top, 2)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Calendar2Style.line)
                .frame(height: 1)
        }
    }

    private func dayHeaderCell(offset: Int) -> some View {
        let date = Calendar2Format.day(offset: offset)
        return VStack(spacing: 3) {
            Text(Calendar2Format.weekday(date))
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundStyle(Calendar2Style.muted)

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(offset == 0 ? .white : Calendar2Style.text2)
                .frame(width: 30, height: 30)
                .background(offset == 0 ? Calendar2Style.accent : .clear, in: Circle())
        }
        .frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                timeColumn
                daysGrid
            }
            .padding(.bottom, 26)
        }
    }

    private var horizontalHistoryDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isSettlingDrag else { return }
                if !isHorizontalDrag {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.8 else { return }
                    isHorizontalDrag = true
                }

                var translation = value.translation.width
                if anchorOffset == -2 && translation < 0 {
                    translation *= 0.22
                }
                dragX = translation
            }
            .onEnded { value in
                guard !isSettlingDrag else { return }
                defer {
                    isHorizontalDrag = false
                }

                guard abs(value.translation.width) > abs(value.translation.height) * 1.8 else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        dragX = 0
                    }
                    return
                }

                let threshold = pagingColumnWidth * 0.3
                let predicted = value.predictedEndTranslation.width
                let shouldMoveOlder = dragX > threshold || predicted > threshold * 1.2
                let shouldMoveNewer = dragX < -threshold || predicted < -threshold * 1.2

                if shouldMoveOlder {
                    settleHorizontalMove(delta: -1, finalDragX: pagingColumnWidth)
                } else if shouldMoveNewer && anchorOffset < -2 {
                    settleHorizontalMove(delta: 1, finalDragX: -pagingColumnWidth)
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        dragX = 0
                    }
                }
            }
    }

    private func settleHorizontalMove(delta: Int, finalDragX: CGFloat) {
        isSettlingDrag = true
        let duration = 0.2
        withAnimation(.easeOut(duration: duration)) {
            dragX = finalDragX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                anchorOffset = min(-2, anchorOffset + delta)
                dragX = 0
                isSettlingDrag = false
            }
        }
    }

    private func moveWindow(by delta: Int) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            anchorOffset = min(-2, anchorOffset + delta)
            dragX = 0
        }
    }

    private var timeColumn: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .frame(width: Calendar2Layout.gutter, height: Calendar2Layout.gridHeight)

            ForEach(Calendar2Layout.hours, id: \.self) { hour in
                Text(Calendar2Format.clock(hour * 60))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Calendar2Style.faint)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(hour - Calendar2Layout.dayStart) * Calendar2Layout.hourHeight - 6)
            }
        }
        .frame(width: Calendar2Layout.gutter)
    }

    private var daysGrid: some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width / 3

            ZStack(alignment: .topLeading) {
                ForEach(Calendar2Layout.hours, id: \.self) { hour in
                    Rectangle()
                        .fill(Calendar2Style.gridLine)
                        .frame(height: 1)
                        .offset(y: CGFloat(hour - Calendar2Layout.dayStart) * Calendar2Layout.hourHeight)
                }

                HStack(spacing: 0) {
                    ForEach(trackOffsets, id: \.self) { offset in
                        calendarDay(offset: offset, width: columnWidth)
                    }
                }
                .offset(x: -columnWidth + dragX)
                .animation(isHorizontalDrag ? nil : .spring(response: 0.3, dampingFraction: 0.88), value: anchorOffset)
                .onAppear {
                    timelineWidth = geo.size.width
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    timelineWidth = newWidth
                }
            }
            .frame(width: geo.size.width, height: Calendar2Layout.gridHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: Calendar2Layout.gridHeight)
    }

    private func calendarDay(offset: Int, width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let layouts = eventLayouts(for: store.events.filter { $0.dayOffset == offset }, now: timeline.date)

            ZStack(alignment: .topLeading) {
                if offset == 0 {
                    Calendar2Style.accent.opacity(0.05)
                }

                ForEach(layouts) { layout in
                    eventBlock(layout, dayWidth: width, now: timeline.date)
                }
            }
            .frame(width: width, height: Calendar2Layout.gridHeight, alignment: .topLeading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Calendar2Style.gridLine)
                    .frame(width: 1)
            }
        }
    }

    private func eventBlock(_ layout: Calendar2EventLayout, dayWidth: CGFloat, now: Date) -> some View {
        let event = layout.event
        let category = store.category(for: event.category)
        let tint = category.color
        let top = CGFloat(event.start - Calendar2Layout.dayStart * 60) / 60 * Calendar2Layout.hourHeight
        let end = event.displayEnd(now: now)
        let height = CGFloat(end - event.start) / 60 * Calendar2Layout.hourHeight
        let isTiny = height < 28
        let horizontalPadding: CGFloat = 3
        let laneGap: CGFloat = 4
        let availableWidth = max(dayWidth - horizontalPadding * 2, 1)
        let laneWidth = max((availableWidth - CGFloat(layout.laneCount - 1) * laneGap) / CGFloat(layout.laneCount), 1)
        let xOffset = horizontalPadding + CGFloat(layout.lane) * (laneWidth + laneGap)

        return Button {
            selectedEvent = event
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: isTiny ? 11 : 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "17191D"))
                    .lineLimit(1)

                if height > 44 {
                    Text("\(Calendar2Format.clock(event.start))-\(Calendar2Format.clock(end))")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: "17191D").opacity(0.58))
                        .lineLimit(1)
                }

                if event.isRunning && height > 30 {
                    Text("进行中")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "17191D").opacity(0.66))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 2)
                    .padding(.vertical, 5)
                }
        }
        .buttonStyle(Calendar2PressStyle())
        .allowsHitTesting(!isHorizontalDrag && !isSettlingDrag)
        .frame(width: laneWidth)
        .frame(height: max(height - 2, Calendar2Layout.minimumEventHeight))
        .offset(x: xOffset, y: top)
    }

    private func eventLayouts(for events: [Calendar2Event], now: Date) -> [Calendar2EventLayout] {
        let sortedEvents = events.sorted {
            if $0.start == $1.start {
                return $0.displayEnd(now: now) > $1.displayEnd(now: now)
            }
            return $0.start < $1.start
        }
        var active: [(event: Calendar2Event, displayEnd: Int, lane: Int, layoutIndex: Int)] = []
        var layouts: [Calendar2EventLayout] = []

        for event in sortedEvents {
            active.removeAll { $0.displayEnd <= event.start }
            let blockingActive = event.prefersFullWidthMidnightLayout ? [] : active.filter {
                !$0.event.prefersFullWidthMidnightLayout &&
                !Calendar2Event.canIgnoreLaneConflict(between: $0.event, activeDisplayEnd: $0.displayEnd, and: event, now: now)
            }
            var lane = 0
            let usedLanes = Set(blockingActive.map(\.lane))
            while usedLanes.contains(lane) {
                lane += 1
            }
            let layoutIndex = layouts.count
            active.append((event, event.layoutEnd(now: now), lane, layoutIndex))
            let laneCount = event.prefersFullWidthMidnightLayout
                ? 1
                : max(max(blockingActive.map(\.lane).max() ?? 0, lane) + 1, 1)
            layouts.append(Calendar2EventLayout(event: event, lane: lane, laneCount: laneCount))
            for activeItem in blockingActive {
                layouts[activeItem.layoutIndex].laneCount = laneCount
            }
        }

        return layouts
    }

    private func createEvent(_ event: Calendar2Event) {
        Task {
            _ = await store.createEvent(event)
        }
    }

    private func saveEditedEvent(_ event: Calendar2Event) {
        Task {
            _ = await store.updateAll(
                id: event.id,
                name: event.name,
                categoryId: event.category,
                typeId: event.typeId,
                start: event.start,
                end: event.end
            )
        }
    }

    private func deleteEvent(id: String) {
        Task {
            if await store.delete(id: id) {
                selectedEvent = nil
            }
        }
    }
}

// MARK: - 编辑 & 新增共用表单

private struct Calendar2EventFormSheet: View {
    enum Mode {
        case edit(Calendar2Event)
        case create(Calendar2Event)
    }

    let mode: Mode
    let categories: [Calendar2Category]
    let categoryProvider: (String) -> Calendar2Category
    let onSave: (Calendar2Event) -> Void
    let onDelete: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String
    @State private var pickedCategory: String
    @State private var pickedType: String?
    @State private var pickedDayOffset: Int
    @State private var start: Int
    @State private var end: Int
    @State private var isSaving = false

    init(
        mode: Mode,
        categories: [Calendar2Category],
        categoryProvider: @escaping (String) -> Calendar2Category,
        onSave: @escaping (Calendar2Event) -> Void,
        onDelete: ((String) -> Void)?
    ) {
        self.mode = mode
        self.categories = categories
        self.categoryProvider = categoryProvider
        self.onSave = onSave
        self.onDelete = onDelete
        let source: Calendar2Event
        switch mode {
        case .edit(let e), .create(let e): source = e
        }
        _draftName = State(initialValue: source.name)
        _pickedCategory = State(initialValue: source.category)
        _pickedType = State(initialValue: source.typeId)
        _pickedDayOffset = State(initialValue: source.dayOffset)
        _start = State(initialValue: source.start)
        _end = State(initialValue: source.end)
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var originalEvent: Calendar2Event? {
        if case .edit(let e) = mode { return e }
        return nil
    }

    private var category: Calendar2Category { categoryProvider(pickedCategory) }
    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && end > start && !isSaving }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // 标题行
                HStack(spacing: 10) {
                    Circle().fill(category.color).frame(width: 12, height: 12)
                    Text(isEdit ? "编辑记录" : "新建记录")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Calendar2Style.text)
                    Spacer()
                    if isEdit, let onDelete, let event = originalEvent {
                        Button(role: .destructive) {
                            onDelete(event.id)
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.8))
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(Calendar2PressStyle())
                    }
                }

                // 名称
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("名称")
                    TextField("输入事件名称", text: $draftName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Calendar2Style.text)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Calendar2Style.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Calendar2Style.line2, lineWidth: 1)
                        )
                }

                // 时长 & 起止展示
                HStack(spacing: 0) {
                    metricView(title: "时长", value: Calendar2Format.duration(max(end - start, 0)), tint: Calendar2Style.accent)
                    Rectangle().fill(Calendar2Style.surface).frame(width: 1).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("起止")
                        Text("\(Calendar2Format.clock(start)) - \(Calendar2Format.clock(end))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Calendar2Style.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(Calendar2Style.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // 时间选择器
                timeEditors
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Calendar2Style.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Calendar2Style.line, lineWidth: 1)
                    )

                // 大类
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("分类")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(categories) { item in
                            let isOn = pickedCategory == item.id
                            Button {
                                if pickedCategory != item.id {
                                    pickedCategory = item.id
                                    pickedType = item.types.first?.id
                                    draftName = item.types.first?.label ?? item.label
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle().fill(item.color).frame(width: 9, height: 9)
                                    Text(item.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isOn ? .white : Calendar2Style.text2)
                                }
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(
                                    isOn ? item.color.opacity(0.18) : Calendar2Style.surface,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isOn ? item.color : Calendar2Style.line2, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(Calendar2PressStyle())
                        }
                    }

                    // 小类
                    Text("小类")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Calendar2Style.faint)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(categoryProvider(pickedCategory).types) { type in
                            let isOn = pickedType == type.id
                            let tint = categoryProvider(pickedCategory).color
                            Button {
                                pickedType = type.id
                                draftName = type.label
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(tint).frame(width: 8, height: 8)
                                    Text(type.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isOn ? tint : Calendar2Style.text2)
                                }
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(isOn ? tint.opacity(0.12) : Calendar2Style.surface, in: Capsule())
                                .overlay(Capsule().stroke(isOn ? tint : tint.opacity(0.35), lineWidth: 1.5))
                            }
                            .buttonStyle(Calendar2PressStyle())
                        }
                    }
                }

                // 保存按钮
                Button { commit() } label: {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(
                            canSave ? Calendar2Style.accent : Calendar2Style.faint,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(Calendar2PressStyle())
                .disabled(!canSave)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 32)
        }
        .background(Calendar2Style.sheet)
    }

    private func commit() {
        guard canSave else { return }
        isSaving = true
        let original = originalEvent
        let event = Calendar2Event(
            id: original?.id ?? "",
            sourceEventId: original?.sourceEventId,
            absoluteStartedAt: original?.absoluteStartedAt,
            absoluteEndedAt: original?.absoluteEndedAt,
            dayOffset: pickedDayOffset,
            start: start,
            end: end,
            name: trimmedName,
            category: pickedCategory,
            typeId: pickedType,
            source: original?.source ?? "manual",
            note: original?.note
        )
        onSave(event)
        dismiss()
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Calendar2Style.muted)
    }

    private func metricView(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeEditors: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日期").font(.system(size: 13, weight: .semibold)).foregroundStyle(Calendar2Style.text2)
                Spacer()
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
            }
            HStack {
                Text("开始").font(.system(size: 13, weight: .semibold)).foregroundStyle(Calendar2Style.text2)
                Spacer()
                DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden().datePickerStyle(.compact)
            }
            HStack {
                Text("结束").font(.system(size: 13, weight: .semibold)).foregroundStyle(Calendar2Style.text2)
                Spacer()
                DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden().datePickerStyle(.compact)
            }
        }
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


struct Calendar2Event: Identifiable, Equatable {
    let id: String
    let sourceEventId: String
    let absoluteStartedAt: Date
    let absoluteEndedAt: Date?
    var dayOffset: Int
    var start: Int
    var end: Int
    var name: String
    var category: String
    var typeId: String?
    var source: String?
    var note: String?
    var isRunning: Bool
    var spansMultipleDays: Bool

    init(id: String, sourceEventId: String? = nil, absoluteStartedAt: Date? = nil, absoluteEndedAt: Date? = nil, dayOffset: Int, start: Int, end: Int, name: String, category: String, typeId: String? = nil, source: String? = nil, note: String? = nil, isRunning: Bool = false, spansMultipleDays: Bool = false) {
        self.id = id
        self.sourceEventId = sourceEventId ?? id
        self.absoluteStartedAt = absoluteStartedAt ?? Calendar2Format.date(dayOffset: dayOffset, minute: start)
        self.absoluteEndedAt = absoluteEndedAt ?? Calendar2Format.date(dayOffset: dayOffset, minute: end)
        self.dayOffset = dayOffset
        self.start = start
        self.end = end
        self.name = name
        self.category = category
        self.typeId = typeId
        self.source = source
        self.note = note
        self.isRunning = isRunning
        self.spansMultipleDays = spansMultipleDays
    }

    static func segments(response: TimeEventResponse, now: Date = .now) -> [Calendar2Event] {
        let calendar = Calendar.current
        let startedAt = response.startedAt
        let effectiveEnd = response.endedAt ?? now
        let segmentationEnd = Calendar2Format.segmentationEnd(start: startedAt, end: effectiveEnd)
        let firstDay = calendar.startOfDay(for: startedAt)
        let lastDay = calendar.startOfDay(for: segmentationEnd)
        let segmentCount = max(calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0, 0) + 1
        let spansMultipleDays = segmentCount > 1

        return (0..<segmentCount).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: firstDay),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }

            let segmentStartDate = max(startedAt, day)
            let segmentEndDate = min(effectiveEnd, nextDay)
            guard segmentEndDate > segmentStartDate else { return nil }

            let segmentStart = Calendar2Format.minute(fromDate: segmentStartDate)
            let segmentEnd = segmentEndDate == nextDay ? Calendar2Layout.dayEnd * 60 : Calendar2Format.minute(fromDate: segmentEndDate)

            return Calendar2Event(
                id: spansMultipleDays ? "\(response.id)::\(Calendar2Format.apiDate(day))" : response.id,
                sourceEventId: response.id,
                absoluteStartedAt: startedAt,
                absoluteEndedAt: response.endedAt,
                dayOffset: Calendar2Format.dayOffset(for: day),
                start: segmentStart,
                end: segmentEnd,
                name: response.name,
                category: response.categoryId,
                typeId: response.typeId,
                source: response.source,
                note: response.note,
                isRunning: response.endedAt == nil && index == segmentCount - 1,
                spansMultipleDays: spansMultipleDays
            )
        }
    }

    func displayEnd(now: Date) -> Int {
        guard isRunning else {
            return max(end, start)
        }
        let liveEnd = dayOffset == 0 ? Calendar2Format.minute(fromDate: now) : Calendar2Layout.dayEnd * 60
        return min(max(liveEnd, start + 5), Calendar2Layout.dayEnd * 60)
    }

    func layoutEnd(now: Date) -> Int {
        let minDisplayMinutes = Int((Calendar2Layout.minimumEventHeight / Calendar2Layout.hourHeight * 60).rounded(.up))
        return max(displayEnd(now: now), start + minDisplayMinutes)
    }

    var prefersFullWidthMidnightLayout: Bool {
        let dayStart = Calendar2Layout.dayStart * 60
        guard start == dayStart && spansMultipleDays else {
            return false
        }
        guard end - start >= Calendar2Layout.fullWidthMidnightSleepMinimumMinutes else {
            return false
        }
        return isSleepLike
    }

    private var isSleepLike: Bool {
        name.contains("睡") ||
        name.localizedCaseInsensitiveContains("sleep") ||
        (typeId?.localizedCaseInsensitiveContains("sleep") ?? false)
    }

    static func canIgnoreLaneConflict(between active: Calendar2Event, activeDisplayEnd: Int, and current: Calendar2Event, now: Date) -> Bool {
        let dayStart = Calendar2Layout.dayStart * 60
        guard active.start == dayStart && current.start == dayStart else {
            return false
        }
        guard active.spansMultipleDays || current.spansMultipleDays else {
            return false
        }

        let overlapEnd = min(activeDisplayEnd, current.layoutEnd(now: now))
        let overlapMinutes = overlapEnd - current.start
        return overlapMinutes > 0 && overlapMinutes <= Calendar2Layout.midnightCarryoverLaneToleranceMinutes
    }
}

private struct Calendar2EventLayout: Identifiable {
    var event: Calendar2Event
    var lane: Int
    var laneCount: Int

    var id: String {
        event.id
    }
}

struct Calendar2Category: Identifiable {
    let id: String
    let label: String
    let color: Color
    let types: [Calendar2CategoryType]

    init(id: String, label: String, color: Color, types: [Calendar2CategoryType]) {
        self.id = id
        self.label = label
        self.color = color
        self.types = types
    }

    init(response: TimeCategoryResponse) {
        id = response.id
        label = response.label
        color = Color(hex: response.color.replacingOccurrences(of: "#", with: ""))
        types = response.types.map {
            Calendar2CategoryType(
                id: $0.id,
                label: $0.label,
                color: $0.color.map { Color(hex: $0) }
            )
        }
    }

    static let fallbackCategories: [Calendar2Category] = [
        Calendar2Category(id: "work", label: "工作", color: Color(hex: "7B8AF0"), types: ["上班", "写代码", "开会", "写文档"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "life", label: "生活", color: Color(hex: "3FA9F5"), types: ["吃早饭", "吃午饭", "煮饭", "购物", "做家务"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "health", label: "健康", color: Color(hex: "F08C8C"), types: ["健身训练", "跑步", "洗澡", "冥想"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "family", label: "家庭", color: Color(hex: "F2C14E"), types: ["陪娃", "接娃", "跟爸视频", "陪家人"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "rest", label: "休息", color: Color(hex: "8A8F9C"), types: ["睡觉", "午睡", "发呆", "聚会"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "leisure", label: "娱乐", color: Color(hex: "FF7847"), types: ["玩手机", "看视频", "打游戏", "听音乐"].map { Calendar2CategoryType(id: $0, label: $0) })
    ]

    static func fallback(for id: String) -> Calendar2Category {
        fallbackCategories.first { $0.id == id } ?? fallbackCategories[4]
    }

    func color(for typeId: String?, eventName: String? = nil) -> Color {
        if let matched = resolvedType(for: typeId, eventName: eventName),
           let typeColor = matched.color {
            return typeColor
        }
        return color
    }

    private func resolvedType(for typeId: String?, eventName: String?) -> Calendar2CategoryType? {
        if let typeId,
           let matchedById = types.first(where: { $0.id == typeId }) {
            return matchedById
        }

        guard let eventName else {
            return nil
        }

        let normalizedEventName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEventName.isEmpty else { return nil }

        return types.first {
            $0.label == normalizedEventName || $0.id == normalizedEventName
        }
    }
}

struct Calendar2CategoryType: Identifiable {
    let id: String
    let label: String
    let color: Color?

    init(id: String, label: String, color: Color? = nil) {
        self.id = id
        self.label = label
        self.color = color
    }
}

enum Calendar2Layout {
    static let dayStart = 0
    static let dayEnd = 24
    static let hourHeight: CGFloat = 64
    static let gutter: CGFloat = 48
    static let estimatedColumnWidth: CGFloat = 112
    static let minimumEventHeight: CGFloat = 18
    static let midnightCarryoverLaneToleranceMinutes = 15
    static let fullWidthMidnightSleepMinimumMinutes = 180
    static let hours = Array(dayStart...dayEnd)
    static var gridHeight: CGFloat { CGFloat(dayEnd - dayStart) * hourHeight }
}

private enum Calendar2Style {
    static let bg = Color(hex: "F5F6F8")
    static let sheet = Color(hex: "FFFFFF")
    static let surface = Color(hex: "FFFFFF")
    static let surface2 = Color(hex: "F0F1F4")
    static let line = Color(hex: "E4E6EB")
    static let line2 = Color(hex: "E4E6EB")
    static let gridLine = Color(hex: "E4E6EB")
    static let accent = Color(hex: "FF7847")
    static let text = Color(hex: "1A1C20")
    static let muted = Color(hex: "8A8F9C")
    static let faint = Color(hex: "A0A5AE")
    static let text2 = Color(hex: "6F7480")
}

enum Calendar2Format {
    static func day(offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func dayOffset(for date: Date) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        return Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0
    }

    static func date(dayOffset: Int, minute: Int) -> Date {
        let base = day(offset: dayOffset)
        return Calendar.current.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: base
        ) ?? base
    }

    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func shortRange(_ offsets: [Int]) -> String {
        guard let first = offsets.first, let last = offsets.last else { return "" }
        let start = day(offset: first)
        let end = day(offset: last)
        let startDay = Calendar.current.component(.day, from: start)
        let endDay = Calendar.current.component(.day, from: end)
        return "\(month(start))\(startDay)-\(endDay)日"
    }

    static func clock(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    static func date(fromMinute minuteOfDay: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    static func minute(fromDate date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func segmentationEnd(start: Date, end: Date) -> Date {
        guard end > start else { return start }
        let calendar = Calendar.current
        if calendar.startOfDay(for: end) == end {
            return end.addingTimeInterval(-1)
        }
        return end
    }

    static func defaultStartMinute(date: Date = Date()) -> Int {
        let minute = minute(fromDate: date)
        let rounded = (minute / 15) * 15
        return min(max(rounded, Calendar2Layout.dayStart * 60), Calendar2Layout.dayEnd * 60 - 30)
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func apiDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    static func parseAPIDate(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Invalid date: \(value)")
        )
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)小时\(mins)分" }
        if hours > 0 { return "\(hours)小时" }
        return "\(mins)分钟"
    }
}

private struct Calendar2PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
