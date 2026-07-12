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
    /// 归属的目标/项目 id（服务端快照），编辑界面可改，用于按目标统计时长。
    var goalId: Int?
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
        goalId: Int? = nil,
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
        self.goalId = goalId
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
            source: response.source, note: response.note, goalId: response.goalId,
            isMobileApp: false, now: now
        )
    }

    static func mobileAppSegments(
        id: String, name: String, categoryId: String, typeId: String?,
        startedAt: Date, endedAt: Date?, source: String?, now: Date = .now
    ) -> [Calendar2Event] {
        makeSegments(
            id: id, name: name, categoryId: categoryId, typeId: typeId, colorHex: nil,
            startedAt: startedAt, endedAt: endedAt, source: source, note: nil, goalId: nil,
            isMobileApp: true, now: now
        )
    }

    private static func makeSegments(
        id: String, name: String, categoryId: String, typeId: String?,
        colorHex: String?,
        startedAt: Date, endedAt: Date?, source: String?, note: String?,
        goalId: Int?,
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
                goalId: goalId,
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
    private let rawLabel: String
    /// 服务端的规范名(bootstrap 模板里的中文名)。label 是服务端按请求 locale
    /// 翻译过的文案,不稳定;i18n 反查优先用规范名。
    let canonicalName: String?
    let color: Color
    /// Backend icon name (a lucide glyph id, e.g. "briefcase"). Mapped to an
    /// SF Symbol when a shortcut auto-derives its icon from the big category.
    let icon: String?
    let loadKind: LoadKind?
    let types: [Calendar2CategoryType]

    var label: String {
        Calendar2SystemCatalog
            .categoryL10nKey(id: id, labels: [canonicalName, rawLabel].compactMap { $0 })
            .map { SharedL10n.tr($0) } ?? rawLabel
    }

    init(id: String, label: String, canonicalName: String? = nil, color: Color, icon: String? = nil, loadKind: LoadKind? = nil, types: [Calendar2CategoryType]) {
        self.id = id
        self.rawLabel = label
        self.canonicalName = canonicalName
        self.color = color
        self.icon = icon
        self.loadKind = loadKind
        self.types = types
    }

    init(response: TimeCategoryResponse) {
        id = response.id
        rawLabel = response.label
        canonicalName = response.name
        color = Color(hex: response.color.replacingOccurrences(of: "#", with: ""))
        icon = response.icon
        loadKind = response.loadKind.flatMap(LoadKind.init(rawValue:))
        types = response.types.map {
            Calendar2CategoryType(
                id: $0.id,
                label: $0.label,
                canonicalName: $0.name,
                categoryId: response.id,
                color: $0.color.map { Color(hex: $0) },
                icon: $0.icon,
                loadKindOverride: $0.loadKindOverride.flatMap(LoadKind.init(rawValue:)),
                tracksFocus: $0.tracksFocus ?? false
            )
        }
    }

    static var fallbackCategories: [Calendar2Category] {
        Calendar2SystemCatalog.fallbackCategories
    }

    static func fallback(for id: String) -> Calendar2Category {
        Calendar2SystemCatalog.fallbackCategory(for: id)
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
    private let rawLabel: String
    /// 服务端的规范名(bootstrap 模板里的中文名),i18n 反查的首选依据。
    let canonicalName: String?
    let categoryId: String?
    let color: Color?
    /// Backend icon name (a lucide glyph id, e.g. "dumbbell"). Mapped to an
    /// SF Symbol when a shortcut auto-derives its icon from the small category.
    let icon: String?
    let loadKindOverride: LoadKind?
    let tracksFocus: Bool

    var label: String {
        Calendar2SystemCatalog
            .typeL10nKey(categoryId: categoryId, labels: [canonicalName, rawLabel, id].compactMap { $0 })
            .map { SharedL10n.tr($0) } ?? rawLabel
    }

    init(id: String, label: String, canonicalName: String? = nil, categoryId: String? = nil, color: Color? = nil, icon: String? = nil, loadKindOverride: LoadKind? = nil, tracksFocus: Bool = false) {
        self.id = id
        self.rawLabel = label
        self.canonicalName = canonicalName
        self.categoryId = categoryId
        self.color = color
        self.icon = icon
        self.loadKindOverride = loadKindOverride
        self.tracksFocus = tracksFocus
    }
}

/// 系统预置大类/小类的唯一数据源,与后端 TimeCategoryBootstrapService 的初始化模板对齐。
/// 兜底分类列表和 i18n key 反查都从这张表生成;标了 isLegacy 的是历史版本的预置分类,
/// 只参与老用户数据的 label 反查,不进入兜底列表。
/// 新增预置分类时在这里加 spec,并在 I18n JSON 里补 `calendar.default.<slug>`
/// (及 `.<typeSlug>`)的双语文案。
enum Calendar2SystemCatalog {
    struct TypeSpec {
        /// 服务端的规范名(bootstrap 模板里的中文名),历史兜底数据里也用它当 id。
        let name: String
        /// i18n key 的最后一段:calendar.default.<categorySlug>.<slug>
        let slug: String
        /// 服务端英文 locale 下发、或历史版本用过的 label,用于反查。
        let aliases: [String]
        let isLegacy: Bool

        init(_ name: String, slug: String, aliases: [String] = [], isLegacy: Bool = false) {
            self.name = name
            self.slug = slug
            self.aliases = aliases
            self.isLegacy = isLegacy
        }
    }

    struct CategorySpec {
        /// 兜底数据使用的稳定 id(服务端真实 id 是数字,离线兜底时用不上)。
        let id: String
        /// 服务端的规范名(中文)。
        let name: String
        /// i18n key 段:calendar.default.<slug>
        let slug: String
        let colorHex: String
        /// Lucide 图标名,与后端模板一致。
        let icon: String?
        /// 服务端英文 locale 下发、或历史版本用过的 label,用于反查。
        let aliases: [String]
        let types: [TypeSpec]
        let isLegacy: Bool

        init(_ id: String, name: String, slug: String? = nil, colorHex: String, icon: String? = nil, aliases: [String], types: [TypeSpec], isLegacy: Bool = false) {
            self.id = id
            self.name = name
            self.slug = slug ?? id
            self.colorHex = colorHex
            self.icon = icon
            self.aliases = aliases
            self.types = types
            self.isLegacy = isLegacy
        }

        var l10nKey: String { "calendar.default.\(slug)" }

        func l10nKey(forType type: TypeSpec) -> String { "\(l10nKey).\(type.slug)" }
    }

    /// 每个大类里,新模板小类在前、legacy 小类在后;英文别名一律取服务端
    /// TimeCatalogLabelResolver / messages.properties 的原文,保证反查命中。
    static let categories: [CategorySpec] = [
        CategorySpec("work", name: "工作", colorHex: "4F86F7", icon: "briefcase", aliases: ["Work"], types: [
            TypeSpec("深度工作", slug: "deep_work", aliases: ["Deep work"]),
            TypeSpec("会议沟通", slug: "meetings", aliases: ["Meetings and communication"]),
            TypeSpec("任务处理", slug: "task_processing", aliases: ["Task processing"]),
            TypeSpec("系统维护", slug: "system_maintenance", aliases: ["System maintenance"]),
            TypeSpec("项目管理", slug: "project_management", aliases: ["Project management"]),
            TypeSpec("上班", slug: "office", aliases: ["Office Work"], isLegacy: true),
            TypeSpec("写代码", slug: "coding", aliases: ["Coding"], isLegacy: true),
            TypeSpec("开会", slug: "meeting", aliases: ["Meeting"], isLegacy: true),
            TypeSpec("写文档", slug: "writing", aliases: ["Documentation"], isLegacy: true)
        ]),
        CategorySpec("learning", name: "学习", colorHex: "7B8AF0", icon: "book-open", aliases: ["Learning"], types: [
            TypeSpec("技术学习", slug: "technical_learning", aliases: ["Technical learning"]),
            TypeSpec("语言学习", slug: "language_learning", aliases: ["Language learning"]),
            TypeSpec("阅读学习", slug: "reading", aliases: ["Reading"]),
            TypeSpec("课程培训", slug: "courses", aliases: ["Courses and training"]),
            TypeSpec("练习输出", slug: "practice", aliases: ["Practice and output"])
        ]),
        CategorySpec("health", name: "健康", colorHex: "33B679", icon: "heart-pulse", aliases: ["Health"], types: [
            TypeSpec("力量训练", slug: "strength_training", aliases: ["Strength training"]),
            TypeSpec("有氧运动", slug: "cardio", aliases: ["Cardio"]),
            TypeSpec("散步", slug: "walking", aliases: ["Walking"]),
            TypeSpec("拉伸恢复", slug: "stretching", aliases: ["Stretching and recovery"]),
            TypeSpec("健康管理", slug: "health_management", aliases: ["Health management"]),
            TypeSpec("健身训练", slug: "workout", aliases: ["Workout"], isLegacy: true),
            TypeSpec("跑步", slug: "running", aliases: ["Running"], isLegacy: true),
            TypeSpec("洗澡", slug: "shower", aliases: ["Shower"], isLegacy: true),
            TypeSpec("冥想", slug: "meditation", aliases: ["Meditation"], isLegacy: true)
        ]),
        CategorySpec("family", name: "家庭", colorHex: "F6A623", icon: "home", aliases: ["Family"], types: [
            TypeSpec("陪娃", slug: "kids", aliases: ["Childcare", "Time with Kids"]),
            TypeSpec("接送娃", slug: "school_run", aliases: ["School run"]),
            TypeSpec("家庭事务", slug: "household", aliases: ["Household tasks"]),
            TypeSpec("伴侣时间", slug: "partner_time", aliases: ["Partner time"]),
            TypeSpec("亲友社交", slug: "social", aliases: ["Friends and family"]),
            TypeSpec("接娃", slug: "school_pickup", aliases: ["School Pickup"], isLegacy: true),
            TypeSpec("跟爸视频", slug: "video_call", aliases: ["Video Call with Dad"], isLegacy: true),
            TypeSpec("陪家人", slug: "family_time", aliases: ["Family Time"], isLegacy: true)
        ]),
        CategorySpec("life", name: "生活", colorHex: "9AA0A6", icon: "sparkles", aliases: ["Life"], types: [
            TypeSpec("吃饭饮食", slug: "meals", aliases: ["Meals"]),
            TypeSpec("家务清洁", slug: "cleaning", aliases: ["Cleaning"]),
            TypeSpec("购物采购", slug: "purchasing", aliases: ["Shopping"]),
            TypeSpec("通勤出行", slug: "commute", aliases: ["Commute and travel"]),
            TypeSpec("个人护理", slug: "personal_care", aliases: ["Personal care"]),
            TypeSpec("行政事务", slug: "admin", aliases: ["Admin tasks"]),
            TypeSpec("吃早饭", slug: "breakfast", aliases: ["Breakfast"], isLegacy: true),
            TypeSpec("吃午饭", slug: "lunch", aliases: ["Lunch"], isLegacy: true),
            TypeSpec("煮饭", slug: "cooking", aliases: ["Cooking"], isLegacy: true),
            TypeSpec("购物", slug: "shopping", aliases: ["Shopping"], isLegacy: true),
            TypeSpec("做家务", slug: "chores", aliases: ["Chores"], isLegacy: true)
        ]),
        CategorySpec("leisure", name: "娱乐", colorHex: "FF8A65", icon: "gamepad-2", aliases: ["Leisure"], types: [
            TypeSpec("玩手机", slug: "phone", aliases: ["Phone time", "Phone Time"]),
            TypeSpec("游戏", slug: "games", aliases: ["Games"]),
            TypeSpec("影视音乐", slug: "media", aliases: ["Film and music"]),
            TypeSpec("放松娱乐", slug: "relaxation", aliases: ["Relaxation"]),
            TypeSpec("兴趣爱好", slug: "hobbies", aliases: ["Hobbies"]),
            TypeSpec("看视频", slug: "video", aliases: ["Watching Videos"], isLegacy: true),
            TypeSpec("打游戏", slug: "game", aliases: ["Gaming"], isLegacy: true),
            TypeSpec("听音乐", slug: "music", aliases: ["Music"], isLegacy: true)
        ]),
        CategorySpec("sleep", name: "睡眠", colorHex: "5C6BC0", icon: "moon", aliases: ["Sleep"], types: [
            TypeSpec("夜间睡眠", slug: "night_sleep", aliases: ["Night sleep"]),
            TypeSpec("午觉小睡", slug: "nap", aliases: ["Nap"]),
            TypeSpec("入睡准备", slug: "sleep_prep", aliases: ["Sleep preparation"]),
            TypeSpec("夜醒中断", slug: "sleep_interruption", aliases: ["Night interruption"])
        ]),
        CategorySpec("growth", name: "成长", colorHex: "26A69A", icon: "target", aliases: ["Growth"], types: [
            TypeSpec("每日计划", slug: "daily_plan", aliases: ["Daily plan"]),
            TypeSpec("每日复盘", slug: "daily_review", aliases: ["Daily review"]),
            TypeSpec("目标管理", slug: "goal_management", aliases: ["Goal management"]),
            TypeSpec("记录整理", slug: "organizing", aliases: ["Organizing records"]),
            TypeSpec("思考决策", slug: "decision_making", aliases: ["Thinking and decisions"])
        ]),
        // 服务端对无分类事件按需创建的默认分类,只参与反查,不进入兜底列表。
        CategorySpec("uncategorized", name: "未分类", colorHex: "9AA0A6", icon: "folder", aliases: ["Uncategorized"], types: [
            TypeSpec("未分类", slug: "uncategorized", aliases: ["Uncategorized"])
        ], isLegacy: true),
        // 历史版本的预置大类,新模板已不再创建。
        CategorySpec("rest", name: "休息", colorHex: "8A8F9C", aliases: ["Rest"], types: [
            TypeSpec("睡觉", slug: "sleep", aliases: ["Sleep"], isLegacy: true),
            TypeSpec("午睡", slug: "nap", aliases: ["Nap"], isLegacy: true),
            TypeSpec("发呆", slug: "idle", aliases: ["Downtime"], isLegacy: true),
            TypeSpec("聚会", slug: "gathering", aliases: ["Gathering"], isLegacy: true)
        ], isLegacy: true),
        CategorySpec("mobile-app-sessions", name: "App使用", slug: "mobile_app_sessions", colorHex: "E83030",
                     aliases: ["App Usage"], types: [])
    ]

    static func categoryL10nKey(id: String, labels: [String]) -> String? {
        categories.first { spec in
            spec.id == id || labels.contains(spec.name) || labels.contains { spec.aliases.contains($0) }
        }?.l10nKey
    }

    static func typeL10nKey(categoryId: String?, labels: [String]) -> String? {
        // 服务端的 categoryId 是数字,按大类圈定只对兜底数据生效;
        // 圈不到时全局按规范名/别名反查(规范名全局唯一)。
        if let scoped = categories.first(where: { $0.id == categoryId }),
           let type = scoped.types.first(where: { matches($0, labels) }) {
            return scoped.l10nKey(forType: type)
        }
        for category in categories {
            if let type = category.types.first(where: { matches($0, labels) }) {
                return category.l10nKey(forType: type)
            }
        }
        return nil
    }

    private static func matches(_ type: TypeSpec, _ labels: [String]) -> Bool {
        labels.contains(type.name) || labels.contains { type.aliases.contains($0) }
    }

    static var fallbackCategories: [Calendar2Category] {
        categories.filter { !$0.isLegacy }.map { spec in
            Calendar2Category(
                id: spec.id,
                label: SharedL10n.tr(spec.l10nKey),
                canonicalName: spec.name,
                color: Color(hex: spec.colorHex),
                icon: spec.icon,
                types: spec.types.filter { !$0.isLegacy }.map {
                    Calendar2CategoryType(
                        id: $0.name,
                        label: SharedL10n.tr(spec.l10nKey(forType: $0)),
                        canonicalName: $0.name,
                        categoryId: spec.id
                    )
                }
            )
        }
    }

    static func fallbackCategory(for id: String) -> Calendar2Category {
        let all = fallbackCategories
        return all.first { $0.id == id } ?? all.first { $0.id == "life" } ?? all[0]
    }
}
