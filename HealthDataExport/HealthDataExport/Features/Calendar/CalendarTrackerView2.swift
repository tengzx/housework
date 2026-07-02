import SwiftUI

struct CalendarTrackerView2: View {
    private static let historyLookaheadDays = 7
    private static let maxFlickDays = 7

    @ObservedObject var store: TimeCalendarStore
    @State private var anchorOffset = -2
    @State private var dragX: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var isSettlingDrag = false
    @State private var timelineWidth: CGFloat = 0
    @State private var selectedEvent: Calendar2Event?
    @State private var draftEvent: Calendar2Event?
    @State private var isScrollingVertically = false
    @State private var scrollResetTask: Task<Void, Never>?
    @State private var showMonthPicker = false
    @State private var showMobileAppEvents = false

    private var visibleOffsets: [Int] {
        [anchorOffset, anchorOffset + 1, anchorOffset + 2]
    }

    private var trackOffsets: [Int] {
        (-Self.historyLookaheadDays...(Self.historyLookaheadDays + 2)).map { anchorOffset + $0 }
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
                if showMonthPicker {
                    Calendar2MonthPickerView(
                        anchorOffset: anchorOffset,
                        onSelect: { offset in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                anchorOffset = min(-2, offset - 1)
                                showMonthPicker = false
                            }
                        }
                    )
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
                dayHeader
                timeline
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .simultaneousGesture(horizontalHistoryDrag)
        }
        .sheet(item: $selectedEvent) { event in
            Calendar2EventFormSheet(
                mode: .edit(event),
                store: store,
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
                store: store,
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
        .onChange(of: anchorOffset) { _, _ in
            Task {
                await store.loadVisibleRange(offsets: trackOffsets)
                if showMobileAppEvents {
                    await store.loadMobileAppEvents(offsets: trackOffsets)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        showMonthPicker.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(monthText)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Calendar2Style.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Calendar2Style.muted)
                            .rotationEffect(.degrees(showMonthPicker ? 180 : 0))
                    }
                }
                .buttonStyle(HapticButtonStyle())

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
                showMobileAppEvents.toggle()
                if showMobileAppEvents {
                    Task { await store.loadMobileAppEvents(offsets: trackOffsets) }
                } else {
                    store.clearMobileAppEvents()
                }
            } label: {
                Image(systemName: "iphone")
                    .font(.system(size: 15, weight: showMobileAppEvents ? .bold : .regular))
                    .foregroundStyle(showMobileAppEvents ? Calendar2Style.accent : Calendar2Style.muted)
                    .padding(4)
            }
            .buttonStyle(HapticButtonStyle())

            Button {
                draftEvent = store.makeDraftEvent(dayOffset: min(0, anchorOffset + 2))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Calendar2Style.accent)
                    .padding(4)
            }
            .buttonStyle(HapticButtonStyle())

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
                .buttonStyle(HapticButtonStyle())
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
                .offset(x: -CGFloat(Self.historyLookaheadDays) * columnWidth + dragX)
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
        .frame(height: 58)
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TimelineScrollOffsetKey.self,
                        value: geo.frame(in: .named("timelineScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "timelineScroll")
        .onPreferenceChange(TimelineScrollOffsetKey.self) { _ in
            isScrollingVertically = true
            scrollResetTask?.cancel()
            scrollResetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                isScrollingVertically = false
            }
        }
        .refreshable {
            await store.refresh(offsets: trackOffsets)
            if showMobileAppEvents {
                store.clearMobileAppEvents()
                await store.loadMobileAppEvents(offsets: trackOffsets)
            }
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
                defer { isHorizontalDrag = false }

                guard abs(value.translation.width) > abs(value.translation.height) * 1.8 else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { dragX = 0 }
                    return
                }

                let threshold = pagingColumnWidth * 0.3
                let predicted = value.predictedEndTranslation.width
                let travel = abs(predicted) > abs(dragX) ? predicted : dragX
                let dayCount = min(
                    max(Int((abs(travel) / pagingColumnWidth).rounded()), 1),
                    Self.maxFlickDays
                )
                let shouldMoveOlder = dragX > threshold || predicted > threshold * 1.2
                let shouldMoveNewer = dragX < -threshold || predicted < -threshold * 1.2

                if shouldMoveOlder {
                    settleHorizontalMove(delta: -dayCount, currentDragX: dragX)
                } else if shouldMoveNewer && anchorOffset < -2 {
                    let limitedDayCount = min(dayCount, -2 - anchorOffset)
                    settleHorizontalMove(delta: limitedDayCount, currentDragX: dragX)
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { dragX = 0 }
                }
            }
    }

    private func settleHorizontalMove(delta: Int, currentDragX: CGFloat) {
        isSettlingDrag = true
        let compensatedDragX = currentDragX + CGFloat(delta) * pagingColumnWidth
        let duration = min(0.34, 0.16 + Double(abs(delta)) * 0.025)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            anchorOffset = min(-2, anchorOffset + delta)
            dragX = compensatedDragX
        }

        withAnimation(.easeOut(duration: duration)) {
            dragX = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragX = 0
                isSettlingDrag = false
            }
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
                .offset(x: -CGFloat(Self.historyLookaheadDays) * columnWidth + dragX)
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
            let regularLayouts = eventLayouts(
                for: store.events.filter { $0.dayOffset == offset },
                now: timeline.date
            )
            let mobileLayouts = showMobileAppEvents
                ? store.mobileAppEvents.filter { $0.dayOffset == offset }
                    .map { Calendar2EventLayout(event: $0, lane: 0, laneCount: 1) }
                : []

            ZStack(alignment: .topLeading) {
                if offset == 0 {
                    Calendar2Style.accent.opacity(0.05)
                }
                ForEach(regularLayouts) { layout in
                    Calendar2EventBlockView(
                        layout: layout,
                        category: store.category(for: layout.event.category),
                        dayWidth: width,
                        isInteractive: !isHorizontalDrag && !isSettlingDrag && !isScrollingVertically,
                        now: timeline.date,
                        onTap: { selectedEvent = layout.event }
                    )
                }
                ForEach(mobileLayouts) { layout in
                    Calendar2EventBlockView(
                        layout: layout,
                        category: store.category(for: layout.event.category),
                        dayWidth: width,
                        isInteractive: false,
                        now: timeline.date,
                        onTap: {}
                    )
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
            while usedLanes.contains(lane) { lane += 1 }
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
        Task { _ = await store.createEvent(event) }
    }

    private func saveEditedEvent(_ event: Calendar2Event) {
        Task {
            _ = await store.updateEvent(event)
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

private struct Calendar2EventLayout: Identifiable {
    var event: Calendar2Event
    var lane: Int
    var laneCount: Int

    var id: String { event.id }
}

private struct Calendar2EventBlockView: View {
    let layout: Calendar2EventLayout
    let category: Calendar2Category
    let dayWidth: CGFloat
    let isInteractive: Bool
    let now: Date
    let onTap: () -> Void

    private var event: Calendar2Event { layout.event }
    private var tint: Color {
        event.isMobileApp ? Self.mobileAppColor(for: event.name) : category.color
    }

    private static let mobileAppPalette: [Color] = [
        Color(hex: "E83030"), Color(hex: "E8722A"), Color(hex: "3D8EE8"),
        Color(hex: "6B4EE8"), Color(hex: "E84EAA"), Color(hex: "2ABD6C"),
        Color(hex: "E8B830"), Color(hex: "1AADAD"), Color(hex: "E83E7C"),
        Color(hex: "4E7AE8"), Color(hex: "D4500A"), Color(hex: "1A8A5A"),
    ]

    private static func mobileAppColor(for name: String) -> Color {
        var hash = 5381
        for scalar in name.unicodeScalars {
            hash = (hash &<< 5) &+ hash &+ Int(scalar.value)
        }
        let index = (hash % mobileAppPalette.count + mobileAppPalette.count) % mobileAppPalette.count
        return mobileAppPalette[index]
    }
    private var top: CGFloat {
        CGFloat(event.start - Calendar2Layout.dayStart * 60) / 60 * Calendar2Layout.hourHeight
    }
    private var displayEnd: Int { event.displayEnd(now: now) }
    private var height: CGFloat {
        CGFloat(displayEnd - event.start) / 60 * Calendar2Layout.hourHeight
    }
    private var isTiny: Bool { height < 28 }
    private var laneWidth: CGFloat {
        let pad: CGFloat = 3
        let gap: CGFloat = 4
        let available = max(dayWidth - pad * 2, 1)
        return max((available - CGFloat(layout.laneCount - 1) * gap) / CGFloat(layout.laneCount), 1)
    }
    private var xOffset: CGFloat {
        3 + CGFloat(layout.lane) * (laneWidth + 4)
    }

    var body: some View {
        if event.isMobileApp {
            mobileAppBar
        } else {
            regularBlock
        }
    }

    private var mobileAppBar: some View {
        ZStack(alignment: .topLeading) {
            tint.opacity(0.70)
            if height >= 16 {
                Text(event.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
        .frame(width: laneWidth)
        .frame(height: max(height, 2))
        .offset(x: xOffset, y: top)
    }

    private var regularBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.name)
                .font(.system(size: isTiny ? 11 : 13, weight: .semibold))
                .foregroundStyle(Color(hex: "17191D"))
                .lineLimit(1)

            if height > 44 {
                Text("\(Calendar2Format.clock(event.start))-\(Calendar2Format.clock(displayEnd))")
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
        .background(tint.opacity(event.isPending ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(width: 2)
                .padding(.vertical, 5)
        }
        .overlay {
            if event.isPending {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .foregroundStyle(tint)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    guard isInteractive else { return }
                    Haptics.tap()
                    onTap()
                }
        )
        .frame(width: laneWidth)
        .frame(height: max(height - 2, Calendar2Layout.minimumEventHeight))
        .offset(x: xOffset, y: top)
    }
}

private struct Calendar2MonthPickerView: View {
    let anchorOffset: Int
    let onSelect: (Int) -> Void

    @State private var displayMonth: Date

    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    init(anchorOffset: Int, onSelect: @escaping (Int) -> Void) {
        self.anchorOffset = anchorOffset
        self.onSelect = onSelect
        let center = Calendar2Format.day(offset: anchorOffset + 1)
        let comps = Calendar.current.dateComponents([.year, .month], from: center)
        _displayMonth = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    private var visibleOffsets: Set<Int> {
        Set([anchorOffset, anchorOffset + 1, anchorOffset + 2])
    }

    var body: some View {
        VStack(spacing: 0) {
            monthNav
            weekdayRow
            dayGrid
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Calendar2Style.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Calendar2Style.line)
                .frame(height: 1)
        }
    }

    private var monthNav: some View {
        HStack {
            Button {
                displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Calendar2Style.accent)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(HapticButtonStyle())

            Spacer()

            Text(monthYearText(displayMonth))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Calendar2Style.text)

            Spacer()

            Button {
                if let next = cal.date(byAdding: .month, value: 1, to: displayMonth) {
                    displayMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Calendar2Style.accent)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(HapticButtonStyle())
        }
        .padding(.vertical, 8)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Calendar2Style.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }

    private var dayGrid: some View {
        let cells = monthCells(for: displayMonth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(0..<cells.count, id: \.self) { i in
                if let date = cells[i] {
                    dayCellView(date: date)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func dayCellView(date: Date) -> some View {
        let offset = Calendar2Format.dayOffset(for: date)
        let isFuture = cal.startOfDay(for: date) > today
        let isToday = cal.isDate(date, inSameDayAs: today)
        let isVisible = visibleOffsets.contains(offset)
        let dayNum = cal.component(.day, from: date)

        return Button {
            guard !isFuture else { return }
            onSelect(offset)
        } label: {
            Text("\(dayNum)")
                .font(.system(size: 16, weight: isToday ? .bold : .regular, design: .rounded))
                .foregroundStyle(
                    isFuture ? Calendar2Style.faint :
                    isToday ? .white :
                    Calendar2Style.text
                )
                .frame(width: 36, height: 36)
                .background {
                    if isToday {
                        Circle().fill(Calendar2Style.accent)
                    } else if isVisible {
                        Circle().fill(Calendar2Style.accent.opacity(0.15))
                    }
                }
        }
        .buttonStyle(HapticButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(isFuture)
    }

    private func monthCells(for date: Date) -> [Date?] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let weekday = cal.component(.weekday, from: first)
        let count = cal.range(of: .day, in: .month, for: date)!.count
        var cells: [Date?] = Array(repeating: nil, count: weekday - 1)
        for i in 0..<count {
            cells.append(cal.date(byAdding: .day, value: i, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func monthYearText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月"
        return fmt.string(from: date)
    }
}

private struct TimelineScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
