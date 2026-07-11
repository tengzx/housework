import SwiftUI

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
    var colorHex: String?
    var source: String?
    var note: String?
    var isRunning: Bool
    var spansMultipleDays: Bool
    var isMobileApp: Bool
    var isPending: Bool

    init(
        id: String,
        sourceEventId: String? = nil,
        absoluteStartedAt: Date? = nil,
        absoluteEndedAt: Date? = nil,
        dayOffset: Int,
        start: Int,
        end: Int,
        name: String,
        category: String,
        typeId: String? = nil,
        colorHex: String? = nil,
        source: String? = nil,
        note: String? = nil,
        isRunning: Bool = false,
        spansMultipleDays: Bool = false,
        isMobileApp: Bool = false,
        isPending: Bool = false
    ) {
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
        self.colorHex = colorHex
        self.source = source
        self.note = note
        self.isRunning = isRunning
        self.spansMultipleDays = spansMultipleDays
        self.isMobileApp = isMobileApp
        self.isPending = isPending
    }

    static func segments(response: TimeEventResponse, now: Date = .now) -> [Calendar2Event] {
        makeSegments(
            id: response.id, name: response.name, categoryId: response.categoryId,
            typeId: response.typeId, colorHex: response.resolvedColor,
            startedAt: response.startedAt, endedAt: response.endedAt,
            source: response.source, note: response.note, isMobileApp: false, now: now
        )
    }

    static func mobileAppSegments(
        id: String, name: String, categoryId: String, typeId: String?,
        startedAt: Date, endedAt: Date?, source: String?, now: Date = .now
    ) -> [Calendar2Event] {
        makeSegments(
            id: id, name: name, categoryId: categoryId, typeId: typeId, colorHex: nil,
            startedAt: startedAt, endedAt: endedAt, source: source, note: nil,
            isMobileApp: true, now: now
        )
    }

    private static func makeSegments(
        id: String, name: String, categoryId: String, typeId: String?,
        colorHex: String?,
        startedAt: Date, endedAt: Date?, source: String?, note: String?,
        isMobileApp: Bool, now: Date
    ) -> [Calendar2Event] {
        let calendar = Calendar.current
        let effectiveEnd = endedAt ?? now
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
            let segmentEnd = segmentEndDate == nextDay
                ? Calendar2Layout.dayEnd * 60
                : Calendar2Format.minute(fromDate: segmentEndDate)
            return Calendar2Event(
                id: spansMultipleDays ? "\(id)::\(Calendar2Format.apiDate(day))" : id,
                sourceEventId: id,
                absoluteStartedAt: startedAt,
                absoluteEndedAt: endedAt,
                dayOffset: Calendar2Format.dayOffset(for: day),
                start: segmentStart,
                end: segmentEnd,
                name: name,
                category: categoryId,
                typeId: typeId,
                colorHex: colorHex,
                source: source,
                note: note,
                isRunning: endedAt == nil && index == segmentCount - 1,
                spansMultipleDays: spansMultipleDays,
                isMobileApp: isMobileApp
            )
        }
    }

    func displayEnd(now: Date) -> Int {
        guard isRunning else { return max(end, start) }
        let liveEnd = dayOffset == 0 ? Calendar2Format.minute(fromDate: now) : Calendar2Layout.dayEnd * 60
        return min(max(liveEnd, start + 5), Calendar2Layout.dayEnd * 60)
    }

    func layoutEnd(now: Date) -> Int {
        guard !isMobileApp else { return displayEnd(now: now) }
        let minDisplayMinutes = Int((Calendar2Layout.laneConflictMinimumHeight / Calendar2Layout.hourHeight * 60).rounded(.up))
        return max(displayEnd(now: now), start + minDisplayMinutes)
    }

    var prefersFullWidthMidnightLayout: Bool {
        let dayStart = Calendar2Layout.dayStart * 60
        guard start == dayStart && spansMultipleDays else { return false }
        guard end - start >= Calendar2Layout.fullWidthMidnightSleepMinimumMinutes else { return false }
        return isSleepLike
    }

    private var isSleepLike: Bool {
        name.contains("睡") ||
        name.localizedCaseInsensitiveContains("sleep") ||
        (typeId?.localizedCaseInsensitiveContains("sleep") ?? false)
    }

    static func canIgnoreLaneConflict(
        between active: Calendar2Event,
        activeDisplayEnd: Int,
        and current: Calendar2Event,
        now: Date
    ) -> Bool {
        let dayStart = Calendar2Layout.dayStart * 60
        guard active.start == dayStart && current.start == dayStart else { return false }
        guard active.spansMultipleDays || current.spansMultipleDays else { return false }
        let overlapEnd = min(activeDisplayEnd, current.layoutEnd(now: now))
        let overlapMinutes = overlapEnd - current.start
        return overlapMinutes > 0 && overlapMinutes <= Calendar2Layout.midnightCarryoverLaneToleranceMinutes
    }
}

struct Calendar2Category: Identifiable {
    let id: String
    let label: String
    let color: Color
    /// Backend icon name (a lucide glyph id, e.g. "briefcase"). Mapped to an
    /// SF Symbol when a shortcut auto-derives its icon from the big category.
    let icon: String?
    let loadKind: LoadKind?
    let types: [Calendar2CategoryType]

    init(id: String, label: String, color: Color, icon: String? = nil, loadKind: LoadKind? = nil, types: [Calendar2CategoryType]) {
        self.id = id
        self.label = label
        self.color = color
        self.icon = icon
        self.loadKind = loadKind
        self.types = types
    }

    init(response: TimeCategoryResponse) {
        id = response.id
        label = response.label
        color = Color(hex: response.color.replacingOccurrences(of: "#", with: ""))
        icon = response.icon
        loadKind = response.loadKind.flatMap(LoadKind.init(rawValue:))
        types = response.types.map {
            Calendar2CategoryType(id: $0.id, label: $0.label, color: $0.color.map { Color(hex: $0) }, icon: $0.icon, loadKindOverride: $0.loadKindOverride.flatMap(LoadKind.init(rawValue:)), tracksFocus: $0.tracksFocus ?? false)
        }
    }

    static let fallbackCategories: [Calendar2Category] = [
        Calendar2Category(id: "work",    label: "工作", color: Color(hex: "7B8AF0"), types: ["上班", "写代码", "开会", "写文档"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "life",    label: "生活", color: Color(hex: "3FA9F5"), types: ["吃早饭", "吃午饭", "煮饭", "购物", "做家务"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "health",  label: "健康", color: Color(hex: "F08C8C"), types: ["健身训练", "跑步", "洗澡", "冥想"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "family",  label: "家庭", color: Color(hex: "F2C14E"), types: ["陪娃", "接娃", "跟爸视频", "陪家人"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "rest",    label: "休息", color: Color(hex: "8A8F9C"), types: ["睡觉", "午睡", "发呆", "聚会"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "leisure", label: "娱乐", color: Color(hex: "FF7847"), types: ["玩手机", "看视频", "打游戏", "听音乐"].map { Calendar2CategoryType(id: $0, label: $0) }),
        Calendar2Category(id: "mobile-app-sessions", label: "App使用", color: Color(hex: "E83030"), types: [])
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
        if let typeId, let matchedById = types.first(where: { $0.id == typeId }) {
            return matchedById
        }
        guard let eventName else { return nil }
        let normalized = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return types.first { $0.label == normalized || $0.id == normalized }
    }
}

struct Calendar2CategoryType: Identifiable {
    let id: String
    let label: String
    let color: Color?
    /// Backend icon name (a lucide glyph id, e.g. "dumbbell"). Mapped to an
    /// SF Symbol when a shortcut auto-derives its icon from the small category.
    let icon: String?
    let loadKindOverride: LoadKind?
    let tracksFocus: Bool

    init(id: String, label: String, color: Color? = nil, icon: String? = nil, loadKindOverride: LoadKind? = nil, tracksFocus: Bool = false) {
        self.id = id
        self.label = label
        self.color = color
        self.icon = icon
        self.loadKindOverride = loadKindOverride
        self.tracksFocus = tracksFocus
    }
}
