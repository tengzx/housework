import SwiftUI

struct CalendarTrackerView2: View {
    private static let historyLookaheadDays = 7
    private static let maxFlickDays = 7
    private static let quickCreateSheetDetent = PresentationDetent.height(320)

    @ObservedObject var store: TimeCalendarStore
    @State private var anchorOffset = -2
    @State private var dragX: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var isSettlingDrag = false
    @State private var timelineWidth: CGFloat = 0
    @State private var selectedEvent: Calendar2Event?
    @State private var draftEvent: Calendar2Event?
    @State private var draftSheetDetent: PresentationDetent = Self.quickCreateSheetDetent
    @State private var isScrollingVertically = false
    @State private var scrollResetTask: Task<Void, Never>?
    @State private var showMonthPicker = false
    @State private var showMobileAppEvents = false
    @State private var timeSelection: Calendar2TimeSelection?
    @State private var showSelectionNameSheet = false
    @State private var adjustingEvent: Calendar2Event?
    @State private var adjustSelection: Calendar2TimeSelection?

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

            if let selection = timeSelection {
                selectionConfirmBar(
                    selection,
                    confirmTitle: "添加事件",
                    onCancel: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            timeSelection = nil
                        }
                    },
                    onConfirm: { openDraftFromSelection() }
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selection = adjustSelection {
                selectionConfirmBar(
                    selection,
                    confirmTitle: "保存",
                    onCancel: { cancelAdjust() },
                    onConfirm: { commitAdjust() }
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
                onDelete: nil,
                onShowDetails: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        draftSheetDetent = .large
                    }
                    DispatchQueue.main.async {
                        draftSheetDetent = .large
                    }
                }
            )
            .presentationDetents([Self.quickCreateSheetDetent, .large], selection: $draftSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(Calendar2Style.sheet)
        }
        .sheet(isPresented: $showSelectionNameSheet) {
            if let selection = timeSelection {
                Calendar2SelectionNameSheet(
                    selection: selection,
                    store: store,
                    onCreated: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            timeSelection = nil
                        }
                    }
                )
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Calendar2Style.sheet)
            }
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
                    HStack(spacing: 6) {
                        Text(monthText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Calendar2Style.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 20, weight: showMobileAppEvents ? .bold : .regular))
                    .foregroundStyle(showMobileAppEvents ? Calendar2Style.accent : Calendar2Style.muted)
                    .padding(4)
            }
            .buttonStyle(HapticButtonStyle())

            Button {
                draftSheetDetent = Self.quickCreateSheetDetent
                draftEvent = store.makeDraftEvent(dayOffset: min(0, anchorOffset + 2))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
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
                        .font(.system(size: 16, weight: .semibold))
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
                for: store.events.filter {
                    $0.dayOffset == offset && $0.sourceEventId != adjustingEvent?.sourceEventId
                },
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
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleEmptyGridTap(offset: offset, locationY: location.y, now: timeline.date)
                    }
                ForEach(regularLayouts) { layout in
                    Calendar2EventBlockView(
                        layout: layout,
                        category: store.category(for: layout.event.category),
                        dayWidth: width,
                        isInteractive: !isHorizontalDrag && !isSettlingDrag && !isScrollingVertically,
                        now: timeline.date,
                        onTap: { beginAdjust(layout.event) },
                        onLongPress: { selectedEvent = layout.event }
                    )
                }
                ForEach(mobileLayouts) { layout in
                    Calendar2EventBlockView(
                        layout: layout,
                        category: store.category(for: layout.event.category),
                        dayWidth: width,
                        isInteractive: false,
                        now: timeline.date,
                        onTap: {},
                        onLongPress: {}
                    )
                }
                if let selection = timeSelection, selection.dayOffset == offset {
                    Calendar2SelectionBlockView(
                        selection: Binding(
                            get: { timeSelection ?? selection },
                            set: { timeSelection = $0 }
                        ),
                        bounds: selectionBounds(dayOffset: offset, selection: selection, now: timeline.date),
                        dayWidth: width,
                        onTapBlock: { openDraftFromSelection() }
                    )
                }
                if let selection = adjustSelection, let adjusting = adjustingEvent, selection.dayOffset == offset {
                    Calendar2SelectionBlockView(
                        selection: Binding(
                            get: { adjustSelection ?? selection },
                            set: { adjustSelection = $0 }
                        ),
                        bounds: selectionBounds(
                            dayOffset: offset,
                            selection: selection,
                            now: timeline.date,
                            excludingSourceId: adjusting.sourceEventId
                        ),
                        dayWidth: width,
                        tint: store.category(for: adjusting.category).color,
                        title: adjusting.name,
                        onTapBlock: { commitAdjust() }
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            timeSelection = nil
        }
        Task { _ = await store.createEvent(event) }
    }

    // MARK: - 点击空白创建（谷歌日历式时间框选择）

    private func handleEmptyGridTap(offset: Int, locationY: CGFloat, now: Date) {
        guard !isHorizontalDrag && !isSettlingDrag && !isScrollingVertically else { return }
        // 正在调整已有事件时，点空白先退出调整模式（不保存），再点才创建新选择框
        if adjustingEvent != nil {
            cancelAdjust()
            return
        }
        let dayStartMin = Calendar2Layout.dayStart * 60
        let dayEndMin = Calendar2Layout.dayEnd * 60
        let tappedMinute = dayStartMin + Int(locationY / Calendar2Layout.hourHeight * 60)

        // 定位点击处所在的空档：下界是点击前（含覆盖点击处）事件的最晚结束，
        // 上界是点击后最早开始的事件。选择框只能放在空档内，不与已有事件重叠。
        var lower = dayStartMin
        var upper = dayEndMin
        for event in store.events where event.dayOffset == offset {
            let eventEnd = event.displayEnd(now: now)
            if event.start <= tappedMinute {
                lower = max(lower, min(eventEnd, dayEndMin))
            }
            if event.start >= tappedMinute {
                upper = min(upper, event.start)
            }
        }
        guard upper - lower >= Calendar2TimeSelection.minDurationMinutes else { return }

        let duration = min(60, upper - lower)
        let snapped = (tappedMinute / Calendar2TimeSelection.tapSnapMinutes) * Calendar2TimeSelection.tapSnapMinutes
        let start = min(max(snapped, lower), upper - duration)
        Haptics.tap()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            timeSelection = Calendar2TimeSelection(dayOffset: offset, start: start, end: start + duration)
        }
    }

    /// 选择框可拖动的边界：下界是上一个事件的结束时间，上界是下一个事件的开始时间。
    /// 调整已有事件时通过 excludingSourceId 排除它自身。
    private func selectionBounds(
        dayOffset: Int,
        selection: Calendar2TimeSelection,
        now: Date,
        excludingSourceId: String? = nil
    ) -> ClosedRange<Int> {
        var lower = Calendar2Layout.dayStart * 60
        var upper = Calendar2Layout.dayEnd * 60
        for event in store.events where event.dayOffset == dayOffset && event.sourceEventId != excludingSourceId {
            let eventEnd = event.displayEnd(now: now)
            if eventEnd <= selection.start {
                lower = max(lower, eventEnd)
            }
            if event.start >= selection.end {
                upper = min(upper, event.start)
            }
        }
        return lower...max(lower + Calendar2TimeSelection.minDurationMinutes, upper)
    }

    // MARK: - 点按事件拖拽调整时间范围（长按打开编辑表单）

    private func beginAdjust(_ event: Calendar2Event) {
        // 进行中、跨天、待服务器确认的事件不支持拖拽调整，仍直接打开编辑表单
        guard !event.isRunning, !event.spansMultipleDays, !event.isPending else {
            selectedEvent = event
            return
        }
        Haptics.tap()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            timeSelection = nil
            adjustingEvent = event
            adjustSelection = Calendar2TimeSelection(
                dayOffset: event.dayOffset,
                start: event.start,
                end: event.end
            )
        }
    }

    private func cancelAdjust() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            adjustingEvent = nil
            adjustSelection = nil
        }
    }

    private func commitAdjust() {
        guard let original = adjustingEvent, let selection = adjustSelection else { return }
        guard selection.start != original.start || selection.end != original.end else {
            cancelAdjust()
            return
        }
        Haptics.tap()
        // 不带绝对时间构造，让事件按新的 start/end 重新计算 startedAt/endedAt；
        // 结束时间为 24:00 时退一分钟，避免超出一天的范围。
        let updated = Calendar2Event(
            id: original.id,
            sourceEventId: original.sourceEventId,
            dayOffset: selection.dayOffset,
            start: selection.start,
            end: min(selection.end, Calendar2Layout.dayEnd * 60 - 1),
            name: original.name,
            category: original.category,
            typeId: original.typeId,
            colorHex: original.colorHex,
            source: original.source,
            note: original.note
        )
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            adjustingEvent = nil
            adjustSelection = nil
        }
        Task { _ = await store.updateEvent(updated) }
    }

    private func openDraftFromSelection() {
        guard timeSelection != nil else { return }
        Haptics.tap()
        showSelectionNameSheet = true
    }

    private func selectionConfirmBar(
        _ selection: Calendar2TimeSelection,
        confirmTitle: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Calendar2Style.muted)
                    .frame(width: 34, height: 34)
                    .background(Calendar2Style.surface2, in: Circle())
            }
            .buttonStyle(HapticButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Calendar2Format.clock(selection.start)) – \(Calendar2Format.clock(selection.end))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Calendar2Style.text)
                Text(Calendar2Format.duration(selection.end - selection.start))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Calendar2Style.muted)
            }

            Spacer()

            Button {
                onConfirm()
            } label: {
                Text(confirmTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Calendar2Style.accent, in: Capsule())
            }
            .buttonStyle(HapticButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Calendar2Style.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 18, x: 0, y: 6)
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
    let onLongPress: () -> Void

    private var event: Calendar2Event { layout.event }
    private var tint: Color {
        if event.isMobileApp {
            return Self.mobileAppColor(for: event.name)
        }
        // 事件块颜色始终跟随所属大类的颜色，忽略小类颜色与服务端下发的快照色，
        // 保证日历与分类列表显示一致。
        return category.color
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
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard isInteractive else { return }
                    Haptics.tap()
                    onLongPress()
                }
        )
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

// MARK: - 时间框选择（点击空白创建）

struct Calendar2TimeSelection: Equatable {
    var dayOffset: Int
    var start: Int
    var end: Int

    /// 拖动手柄时的吸附粒度：1 分钟，可精确调整
    static let snapMinutes = 1
    /// 点击空白创建时起点的对齐粒度
    static let tapSnapMinutes = 15
    static let minDurationMinutes = 15
    /// 拖动时每跨过 5 分钟刻度给一次触觉反馈（1 分钟一震太密）
    static let hapticStepMinutes = 5
}

/// 谷歌日历式选择框：点击空白出现，上下圆点手柄拖动调整起止时间，拖动框体整体平移。
/// 拖动过程中框体连续跟手（不量化），时间值实时吸附到 15 分钟；松手后框体弹回对齐位置。
/// 手势必须用 .global 坐标系：框体会随拖动移动，.local 坐标系下 translation 会被
/// 自身位移污染，产生抖动。
private struct Calendar2SelectionBlockView: View {
    @Binding var selection: Calendar2TimeSelection
    /// 可拖动范围：[上一个事件的结束时间, 下一个事件的开始时间]
    let bounds: ClosedRange<Int>
    let dayWidth: CGFloat
    /// 新建时用主题橙色；调整已有事件时传该事件的分类色。
    var tint: Color = Calendar2Style.accent
    /// 调整已有事件时显示事件名称。
    var title: String? = nil
    let onTapBlock: () -> Void

    @State private var dragAnchor: Calendar2TimeSelection?
    @State private var liveStart: CGFloat?
    @State private var liveEnd: CGFloat?

    private var dayStartMin: Int { Calendar2Layout.dayStart * 60 }
    private var renderStart: CGFloat { liveStart ?? CGFloat(selection.start) }
    private var renderEnd: CGFloat { liveEnd ?? CGFloat(selection.end) }
    private var top: CGFloat {
        (renderStart - CGFloat(dayStartMin)) / 60 * Calendar2Layout.hourHeight
    }
    private var height: CGFloat {
        (renderEnd - renderStart) / 60 * Calendar2Layout.hourHeight
    }
    private let handleSize: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.13))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(tint, lineWidth: 2)

            if height > 40 {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "17191D"))
                            .lineLimit(1)
                    }
                    Text("\(Calendar2Format.clock(selection.start))-\(Calendar2Format.clock(selection.end))")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                .padding(.horizontal, 7)
                .padding(.top, 6)
            }
        }
        .frame(width: max(dayWidth - 6, 1), height: max(height, 12))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { onTapBlock() }
        .highPriorityGesture(moveDrag)
        .overlay(alignment: .topLeading) {
            handle.highPriorityGesture(edgeDrag(isTop: true))
                .offset(x: -handleSize / 2 + 4, y: -handleSize / 2)
        }
        .overlay(alignment: .bottomTrailing) {
            handle.highPriorityGesture(edgeDrag(isTop: false))
                .offset(x: handleSize / 2 - 4, y: handleSize / 2)
        }
        .offset(x: 3, y: top)
    }

    private var handle: some View {
        Circle()
            .fill(tint)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            // 扩大触控区域，避免手柄太小难以命中
            .padding(10)
            .contentShape(Circle())
            .padding(-10)
    }

    private func snap(_ minute: CGFloat) -> Int {
        let unit = CGFloat(Calendar2TimeSelection.snapMinutes)
        return Int((minute / unit).rounded()) * Calendar2TimeSelection.snapMinutes
    }

    private func deltaMinutes(_ translation: CGFloat) -> CGFloat {
        translation / Calendar2Layout.hourHeight * 60
    }

    private func settleDragEnd() {
        dragAnchor = nil
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            liveStart = nil
            liveEnd = nil
        }
    }

    private func hapticIfCrossedStep(from old: Int, to new: Int) {
        let step = Calendar2TimeSelection.hapticStepMinutes
        if old / step != new / step {
            Haptics.tap()
        }
    }

    private func edgeDrag(isTop: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let anchor = dragAnchor ?? selection
                if dragAnchor == nil { dragAnchor = anchor }
                let delta = deltaMinutes(value.translation.height)
                if isTop {
                    let continuous = min(
                        max(CGFloat(anchor.start) + delta, CGFloat(bounds.lowerBound)),
                        CGFloat(anchor.end - Calendar2TimeSelection.minDurationMinutes)
                    )
                    liveStart = continuous
                    let snapped = min(
                        max(snap(continuous), bounds.lowerBound),
                        anchor.end - Calendar2TimeSelection.minDurationMinutes
                    )
                    if snapped != selection.start {
                        hapticIfCrossedStep(from: selection.start, to: snapped)
                        selection.start = snapped
                    }
                } else {
                    let continuous = max(
                        min(CGFloat(anchor.end) + delta, CGFloat(bounds.upperBound)),
                        CGFloat(anchor.start + Calendar2TimeSelection.minDurationMinutes)
                    )
                    liveEnd = continuous
                    let snapped = max(
                        min(snap(continuous), bounds.upperBound),
                        anchor.start + Calendar2TimeSelection.minDurationMinutes
                    )
                    if snapped != selection.end {
                        hapticIfCrossedStep(from: selection.end, to: snapped)
                        selection.end = snapped
                    }
                }
            }
            .onEnded { _ in settleDragEnd() }
    }

    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                let anchor = dragAnchor ?? selection
                if dragAnchor == nil { dragAnchor = anchor }
                let duration = anchor.end - anchor.start
                let delta = deltaMinutes(value.translation.height)
                let continuous = min(
                    max(CGFloat(anchor.start) + delta, CGFloat(bounds.lowerBound)),
                    CGFloat(max(bounds.upperBound - duration, bounds.lowerBound))
                )
                liveStart = continuous
                liveEnd = continuous + CGFloat(duration)
                let snapped = min(
                    max(snap(continuous), bounds.lowerBound),
                    max(bounds.upperBound - duration, bounds.lowerBound)
                )
                if snapped != selection.start {
                    hapticIfCrossedStep(from: selection.start, to: snapped)
                    selection.start = snapped
                    selection.end = snapped + duration
                }
            }
            .onEnded { _ in settleDragEnd() }
    }
}

/// 框选时间后的补录弹框：时间范围已由选择框确定，用户只输入事件名称。
/// 保存时把时间范围拼进文本走自然语言接口，让后端按名称自动归类。
private struct Calendar2SelectionNameSheet: View {
    let selection: Calendar2TimeSelection
    @ObservedObject var store: TimeCalendarStore
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage = ""
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("这段时间做了什么？")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "111115"))
                .padding(.bottom, 12)

            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Calendar2Format.clock(selection.start)) – \(Calendar2Format.clock(selection.end))")
                    .monospacedDigit()
                Text("· \(Calendar2Format.duration(selection.end - selection.start))")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Calendar2Style.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Calendar2Style.accent.opacity(0.12), in: Capsule())
            .padding(.bottom, 16)

            TextField("输入事件名称，例如 写代码", text: $name)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "23232A"))
                .tint(Calendar2Style.accent)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "E5564B"))
                    .padding(.top, 10)
            }

            Spacer(minLength: 16)

            Button { commit() } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("保存")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    canSave ? Calendar2Style.accent : Calendar2Style.faint,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(Calendar2PressStyle())
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isNameFocused = true
            }
        }
    }

    private func commit() {
        guard canSave else { return }
        isSaving = true
        errorMessage = ""
        // 拼上框选的时间范围，让后端只需按名称推断分类。
        // 结束时间拉到当天最底部时是 24:00，超出后端可解析的范围，改用 23:59 提交。
        let endMinute = min(selection.end, Calendar2Layout.dayEnd * 60 - 1)
        let text = "\(Calendar2Format.clock(selection.start))到\(Calendar2Format.clock(endMinute))\(trimmedName)"
        Task {
            if await store.createNaturalLanguageEvent(text: text, dayOffset: selection.dayOffset) != nil {
                onCreated()
                dismiss()
            } else {
                errorMessage = store.statusMessage.isEmpty ? "保存失败，请重试" : store.statusMessage
                isSaving = false
            }
        }
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
