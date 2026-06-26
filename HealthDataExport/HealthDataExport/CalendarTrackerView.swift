import SwiftUI

// ============================================================================
// 时间追踪 · 日历视图（统计界面）—— 3 天并排，按大类上色
// 左右拖动看历史；点色块弹详情，可改大类 + 小类 + 起止时间
// 暂不接接口：下面 seedEvents 是演示数据。
// ============================================================================

// MARK: - 配色与分类

struct TrackCategory {
    let label: String
    let color: Color
    let subs: [String]
}

enum CalendarPalette {
    static let categories: [String: TrackCategory] = [
        "work":    TrackCategory(label: "工作", color: Color(hex: "7B8AF0"), subs: ["上班", "写代码", "开会", "写文档"]),
        "life":    TrackCategory(label: "生活", color: Color(hex: "3FA9F5"), subs: ["吃早饭", "吃午饭", "煮饭", "购物", "做家务"]),
        "health":  TrackCategory(label: "健康", color: Color(hex: "F08C8C"), subs: ["健身训练", "跑步", "洗澡", "冥想"]),
        "family":  TrackCategory(label: "家庭", color: Color(hex: "F2C14E"), subs: ["陪娃", "接娃", "跟爸视频", "陪家人"]),
        "rest":    TrackCategory(label: "休息", color: Color(hex: "8A8F9C"), subs: ["睡觉", "午睡", "发呆", "聚会"]),
        "leisure": TrackCategory(label: "娱乐", color: Color(hex: "FF7847"), subs: ["玩手机", "看视频", "打游戏", "听音乐"]),
    ]
    static let keys = ["work", "life", "health", "family", "rest", "leisure"]

    static func category(_ key: String) -> TrackCategory {
        categories[key] ?? categories["rest"]!
    }
}

// MARK: - 布局常量

private enum CalLayout {
    static let hourH: CGFloat = 64
    static let dayStart = 0
    static let dayEnd = 24
    static let gutterW: CGFloat = 48
    static var hours: [Int] { Array(dayStart...dayEnd) }
    static var gridHeight: CGFloat { CGFloat(dayEnd - dayStart) * hourH }
}

// MARK: - 事件模型

struct TrackEvent: Identifiable, Equatable {
    let id: Int
    var name: String
    var category: String
    var dayOffset: Int
    var start: Int   // 当天分钟数
    var end: Int
}

private func mm(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

private let seedEvents: [TrackEvent] = {
    let raw: [(d: Int, s: Int, e: Int, name: String, c: String)] = [
        (0, mm(5), mm(8), "睡觉", "rest"),
        (0, mm(8), mm(8, 40), "吃早饭", "life"),
        (0, mm(8, 40), mm(11, 30), "上班", "work"),
        (0, mm(11, 30), mm(12), "煮饭", "life"),
        (0, mm(12), mm(12, 20), "上班", "work"),
        (0, mm(12, 20), mm(13), "吃午饭", "life"),
        (0, mm(13), mm(14, 40), "购物", "rest"),
        (0, mm(14, 40), mm(15, 40), "上班", "work"),
        (-1, mm(5), mm(7), "玩手机", "leisure"),
        (-1, mm(7), mm(8), "睡觉", "rest"),
        (-1, mm(8), mm(9), "吃早饭", "life"),
        (-1, mm(9), mm(9, 45), "陪娃", "family"),
        (-1, mm(9, 45), mm(11, 30), "健身训练", "health"),
        (-1, mm(11, 30), mm(12), "煮饭", "life"),
        (-1, mm(12), mm(12, 30), "吃午饭", "life"),
        (-1, mm(12, 30), mm(13), "陪娃", "family"),
        (-1, mm(13), mm(13, 30), "洗澡", "health"),
        (-1, mm(13, 30), mm(14, 40), "午睡", "rest"),
        (-1, mm(14, 40), mm(15, 40), "玩手机", "leisure"),
        (-1, mm(15, 40), mm(17), "聚会", "rest"),
        (-2, mm(5), mm(5, 45), "玩手机", "leisure"),
        (-2, mm(5, 45), mm(10, 30), "睡觉", "rest"),
        (-2, mm(11, 15), mm(12), "玩手机", "leisure"),
        (-2, mm(14), mm(14, 45), "玩手机", "leisure"),
    ]
    return raw.enumerated().map { i, x in
        TrackEvent(id: i + 1, name: x.name, category: x.c, dayOffset: x.d, start: x.s, end: x.e)
    }
}()

// MARK: - 格式化

private func fmtDur(_ mins: Int) -> String {
    let h = mins / 60, m = mins % 60
    if h > 0 && m > 0 { return "\(h)小时\(m)分" }
    if h > 0 { return "\(h)小时" }
    return "\(m)分钟"
}

private func fmtClock(_ t: Int) -> String {
    String(format: "%02d:%02d", t / 60, t % 60)
}

private func dayDate(offset: Int) -> Date {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return cal.date(byAdding: .day, value: offset, to: today) ?? today
}

// MARK: - Sheet 内容枚举（编辑 & 新增共用）

private enum SheetContent: Identifiable {
    case edit(TrackEvent)
    case add(dayOffset: Int)

    var id: String {
        switch self {
        case .edit(let e): return "edit-\(e.id)"
        case .add(let d): return "add-\(d)"
        }
    }
}

// MARK: - 主视图

struct CalendarTrackerView: View {
    @State private var anchorOffset = -2
    @State private var dragX: CGFloat = 0
    @State private var sheetContent: SheetContent?
    @State private var events: [TrackEvent] = seedEvents

    private var atToday: Bool { anchorOffset == -2 }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: dayDate(offset: anchorOffset))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                dayHeader
                grid
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheetContent) { content in
            EventFormSheet(content: content, onSave: handleSave)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "161617"))
        }
    }

    // MARK: 顶部标题

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(monthLabel)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("时间追踪 · 拖动看历史")
                    .font(.system(size: 12))
                    .tracking(1)
                    .foregroundStyle(Color(hex: "8A8F9C"))
            }
            Spacer()
            Button {
                sheetContent = .add(dayOffset: min(0, anchorOffset + 2))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "C9CDD6"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "1C1C1E"), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    anchorOffset = -2
                    dragX = 0
                }
            } label: {
                Text("今天")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "C9CDD6"))
                    .frame(height: 38)
                    .padding(.horizontal, 16)
                    .background(Color(hex: "1C1C1E"), in: RoundedRectangle(cornerRadius: 12))
            }
            .opacity(atToday ? 0.4 : 1)
            .disabled(atToday)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: 日期表头

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalLayout.gutterW)
            ForEach(0..<3, id: \.self) { i in
                let off = anchorOffset + i
                let date = dayDate(offset: off)
                VStack(spacing: 3) {
                    Text(weekday(date))
                        .font(.system(size: 11))
                        .tracking(1)
                        .foregroundStyle(Color(hex: "8A8F9C"))
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(off == 0 ? .white : Color(hex: "C9CDD6"))
                        .frame(width: 30, height: 30)
                        .background(off == 0 ? Color(hex: "FF7847") : .clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: "1C1C1E")).frame(height: 1)
        }
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    // MARK: 时间网格

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        Color.clear.frame(width: CalLayout.gutterW, height: CalLayout.gridHeight)
                        ForEach(CalLayout.hours, id: \.self) { h in
                            Text(fmtClock(h * 60))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Color(hex: "5A5E68"))
                                .padding(.trailing, 6)
                                .offset(y: CGFloat(h - CalLayout.dayStart) * CalLayout.hourH - 6)
                        }
                    }
                    .frame(width: CalLayout.gutterW)

                    viewport
                }
                .padding(.bottom, 24)
                .id("gridTop")
            }
            .onAppear {
                proxy.scrollTo("gridTop", anchor: .top)
            }
        }
    }

    private var viewport: some View {
        GeometryReader { geo in
            let colW = geo.size.width / 3
            let windowOffsets = [-1, 0, 1, 2, 3].map { anchorOffset + $0 }

            ZStack(alignment: .topLeading) {
                ForEach(CalLayout.hours, id: \.self) { h in
                    Rectangle()
                        .fill(Color(hex: "161617"))
                        .frame(height: 1)
                        .offset(y: CGFloat(h - CalLayout.dayStart) * CalLayout.hourH)
                }

                HStack(spacing: 0) {
                    ForEach(windowOffsets, id: \.self) { off in
                        dayColumn(off: off, width: colW)
                    }
                }
                .offset(x: -colW + dragX)
            }
            .frame(width: geo.size.width, height: CalLayout.gridHeight, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(pageDrag(colW: colW))
        }
        .frame(height: CalLayout.gridHeight)
    }

    private func dayColumn(off: Int, width: CGFloat) -> some View {
        let dayEvents = events.filter { $0.dayOffset == off }
        return ZStack(alignment: .topLeading) {
            if off == 0 {
                Color(hex: "FF7847").opacity(0.04)
            }
            ForEach(dayEvents) { ev in
                eventBlock(ev)
            }
        }
        .frame(width: width, height: CalLayout.gridHeight, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(hex: "161617")).frame(width: 1)
        }
    }

    private func eventBlock(_ ev: TrackEvent) -> some View {
        let cat = CalendarPalette.category(ev.category)
        let top = CGFloat(ev.start - CalLayout.dayStart * 60) / 60 * CalLayout.hourH
        let height = CGFloat(ev.end - ev.start) / 60 * CalLayout.hourH
        let tiny = height < 26
        return Button {
            sheetContent = .edit(ev)
        } label: {
            Text(ev.name)
                .font(.system(size: tiny ? 11 : 13, weight: .semibold))
                .foregroundStyle(Color(hex: "1A1C20"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(height: max(height - 2, 16), alignment: .top)
                .background(cat.color, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .offset(y: top)
    }

    private func pageDrag(colW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                var d = value.translation.width
                if atToday && d > 0 { d *= 0.25 }
                dragX = d
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(.spring()) { dragX = 0 }
                    return
                }
                let threshold = colW * 0.4
                var next = anchorOffset
                if dragX < -threshold { next = anchorOffset + 1 }
                else if dragX > threshold { next = anchorOffset - 1 }
                next = min(-2, next)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    anchorOffset = next
                    dragX = 0
                }
            }
    }

    // MARK: 保存处理

    private func handleSave(_ event: TrackEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            let newId = (events.map(\.id).max() ?? 0) + 1
            events.append(TrackEvent(
                id: newId,
                name: event.name,
                category: event.category,
                dayOffset: event.dayOffset,
                start: event.start,
                end: event.end
            ))
        }
    }
}

// MARK: - 事件表单（编辑 & 新增共用）

private struct EventFormSheet: View {
    let content: SheetContent
    let onSave: (TrackEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draftCategory: String
    @State private var draftName: String
    @State private var draftStart: Int
    @State private var draftEnd: Int

    init(content: SheetContent, onSave: @escaping (TrackEvent) -> Void) {
        self.content = content
        self.onSave = onSave
        switch content {
        case .edit(let event):
            _draftCategory = State(initialValue: event.category)
            _draftName = State(initialValue: event.name)
            _draftStart = State(initialValue: event.start)
            _draftEnd = State(initialValue: event.end)
        case .add:
            let defaultCat = "work"
            _draftCategory = State(initialValue: defaultCat)
            _draftName = State(initialValue: CalendarPalette.categories[defaultCat]!.subs[0])
            _draftStart = State(initialValue: mm(9))
            _draftEnd = State(initialValue: mm(10))
        }
    }

    private var cat: TrackCategory { CalendarPalette.category(draftCategory) }
    private var dur: Int { max(0, draftEnd - draftStart) }
    private var canSave: Bool { !draftName.isEmpty && draftEnd > draftStart }

    private var isEdit: Bool {
        if case .edit = content { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // 标题行
                HStack {
                    Circle().fill(cat.color).frame(width: 12, height: 12)
                    Text(isEdit ? "编辑事件" : "新增事件")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "8A8F9C"))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "1C1C1E"), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // 时长 + 起止显示
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("时长").font(.system(size: 11)).tracking(1.5)
                            .foregroundStyle(Color(hex: "8A8F9C"))
                        Text(fmtDur(dur))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "FF7847"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle().fill(Color(hex: "2C2C2E")).frame(width: 1).padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("起止").font(.system(size: 11)).tracking(1.5)
                            .foregroundStyle(Color(hex: "8A8F9C"))
                        Text("\(fmtClock(draftStart)) – \(fmtClock(draftEnd))")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(Color(hex: "0B0B0C"), in: RoundedRectangle(cornerRadius: 16))

                // 时间选择器
                VStack(spacing: 14) {
                    HStack {
                        Text("开始")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "C9CDD6"))
                        Spacer()
                        DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).colorScheme(.dark)
                    }
                    Divider().background(Color(hex: "2C2C2E"))
                    HStack {
                        Text("结束")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "C9CDD6"))
                        Spacer()
                        DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).colorScheme(.dark)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(Color(hex: "1C1C1E"), in: RoundedRectangle(cornerRadius: 16))

                // 大类
                VStack(alignment: .leading, spacing: 10) {
                    Text("大类").font(.system(size: 11)).tracking(1.5)
                        .foregroundStyle(Color(hex: "8A8F9C"))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(CalendarPalette.keys, id: \.self) { k in
                            let c = CalendarPalette.category(k)
                            let on = k == draftCategory
                            Button {
                                if draftCategory != k {
                                    draftCategory = k
                                    draftName = c.subs.first ?? draftName
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle().fill(c.color).frame(width: 9, height: 9)
                                    Text(c.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(on ? .white : Color(hex: "C9CDD6"))
                                }
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(
                                    on ? c.color.opacity(0.13) : Color(hex: "1C1C1E"),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(on ? c.color : Color(hex: "2C2C2E"), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 小类
                VStack(alignment: .leading, spacing: 10) {
                    Text("小类").font(.system(size: 11)).tracking(1)
                        .foregroundStyle(Color(hex: "5A5E68"))

                    FlowChips(items: CalendarPalette.category(draftCategory).subs) { sub in
                        let on = sub == draftName
                        let c = CalendarPalette.category(draftCategory)
                        Button {
                            draftName = sub
                        } label: {
                            Text(sub)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(on ? .white : Color(hex: "C9CDD6"))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(
                                    on ? c.color.opacity(0.13) : Color(hex: "1C1C1E"),
                                    in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(on ? c.color : Color(hex: "2C2C2E"), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 保存按钮
                Button { save() } label: {
                    Text("保存")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(
                            canSave ? Color(hex: "FF7847") : Color(hex: "3C3C3E"),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private func save() {
        guard canSave else { return }
        let event: TrackEvent
        switch content {
        case .edit(let original):
            event = TrackEvent(
                id: original.id,
                name: draftName,
                category: draftCategory,
                dayOffset: original.dayOffset,
                start: draftStart,
                end: draftEnd
            )
        case .add(let dayOffset):
            event = TrackEvent(
                id: 0,   // handleSave 会分配真实 id
                name: draftName,
                category: draftCategory,
                dayOffset: dayOffset,
                start: draftStart,
                end: draftEnd
            )
        }
        onSave(event)
        dismiss()
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(draftStart) },
            set: { newVal in
                let start = dateToMinutes(newVal)
                draftStart = start
                if draftEnd <= start {
                    draftEnd = min(start + 5, CalLayout.dayEnd * 60)
                }
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(draftEnd) },
            set: { newVal in
                let end = dateToMinutes(newVal)
                draftEnd = max(end, draftStart + 5)
            }
        )
    }

    private func minutesToDate(_ t: Int) -> Date {
        Calendar.current.date(bySettingHour: t / 60, minute: t % 60, second: 0, of: Date()) ?? Date()
    }

    private func dateToMinutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - 简单流式标签布局

private struct FlowChips<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x - bounds.minX + s.width > maxW && x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

#Preview {
    CalendarTrackerView()
}
