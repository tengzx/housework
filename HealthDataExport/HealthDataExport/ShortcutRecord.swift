import Combine
import Foundation
import SwiftUI

struct ShortcutCategory: Identifiable {
    let id: String
    let label: String
    let colorHex: String
    let subtypes: [ShortcutSubtype]
    var color: Color { Color(hex: colorHex) }

    init(id: String, label: String, colorHex: String, subtypes: [ShortcutSubtype]) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
        self.subtypes = subtypes
    }

    fileprivate init(response: RemoteCategoryResponse) {
        id = response.id
        label = response.label
        colorHex = response.color.replacingOccurrences(of: "#", with: "")
        subtypes = response.types.map { ShortcutSubtype(id: $0.id, label: $0.label) }
    }
}

struct ShortcutSubtype: Identifiable {
    let id: String
    let label: String
}

struct ShortcutTask: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbolName: String
    var colorHex: String
    var categoryId: String?
    var subtypeId: String?

    init(id: UUID = UUID(), name: String, symbolName: String, colorHex: String, categoryId: String? = nil, subtypeId: String? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.categoryId = categoryId
        self.subtypeId = subtypeId
    }

    var color: Color {
        Color(hex: colorHex)
    }
}

struct ShortcutEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case started
        case stopped
        case note
    }

    let id: UUID
    var task: ShortcutTask
    var kind: Kind
    var note: String
    var createdAt: Date

    init(id: UUID = UUID(), task: ShortcutTask, kind: Kind, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.task = task
        self.kind = kind
        self.note = note
        self.createdAt = createdAt
    }
}

struct ActiveShortcutSession: Codable, Hashable {
    var task: ShortcutTask
    var startedAt: Date
}

@MainActor
final class ShortcutRecordStore: ObservableObject {
    @Published var tasks: [ShortcutTask]
    @Published var activeSession: ActiveShortcutSession?
    @Published var events: [ShortcutEvent]

    private let tasksKey = "shortcutRecord.tasks"
    private let activeKey = "shortcutRecord.activeSession"
    private let eventsKey = "shortcutRecord.events"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.tasks = Self.load([ShortcutTask].self, key: tasksKey, from: userDefaults) ?? Self.defaultTasks
        self.activeSession = Self.load(ActiveShortcutSession.self, key: activeKey, from: userDefaults)
        self.events = Self.load([ShortcutEvent].self, key: eventsKey, from: userDefaults) ?? Self.defaultEvents
    }

    func addTask(name: String, template: ShortcutTask, categoryId: String?, subtypeId: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        tasks.append(ShortcutTask(name: trimmedName, symbolName: template.symbolName, colorHex: template.colorHex, categoryId: categoryId, subtypeId: subtypeId))
        saveTasks()
    }

    func removeTask(_ task: ShortcutTask) {
        tasks.removeAll { $0.id == task.id }
        if activeSession?.task.id == task.id {
            activeSession = nil
            saveActiveSession()
        }
        saveTasks()
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
        saveTasks()
    }

    func start(_ task: ShortcutTask) {
        activeSession = ActiveShortcutSession(task: task, startedAt: .now)
        events.insert(ShortcutEvent(task: task, kind: .started, note: "开始了"), at: 0)
        saveActiveSession()
        saveEvents()
    }

    func stop(note: String) {
        guard let activeSession else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        events.insert(ShortcutEvent(task: activeSession.task, kind: .stopped, note: trimmedNote.isEmpty ? "结束了" : trimmedNote), at: 0)
        self.activeSession = nil
        saveActiveSession()
        saveEvents()
    }

    func syncRunningSession(_ runningEntry: RunningShortcutEntry?) {
        guard let runningEntry else {
            activeSession = nil
            saveActiveSession()
            return
        }

        let task = tasks.first { $0.name == runningEntry.taskName }
            ?? ShortcutTask(name: runningEntry.taskName, symbolName: "clock.fill", colorHex: "FF7847")
        activeSession = ActiveShortcutSession(task: task, startedAt: runningEntry.startedAt)
        saveActiveSession()
    }

    func addNote(_ note: String, task: ShortcutTask?) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        let eventTask = task ?? tasks.first ?? Self.defaultTasks[0]
        events.insert(ShortcutEvent(task: eventTask, kind: .note, note: trimmedNote), at: 0)
        saveEvents()
    }

    private func saveTasks() {
        Self.save(tasks, key: tasksKey, to: userDefaults)
    }

    private func saveActiveSession() {
        Self.save(activeSession, key: activeKey, to: userDefaults)
    }

    private func saveEvents() {
        Self.save(Array(events.prefix(100)), key: eventsKey, to: userDefaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from userDefaults: UserDefaults) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, to userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }

    nonisolated static let categories: [ShortcutCategory] = [
        ShortcutCategory(id: "work", label: "工作", colorHex: "3F7BF7", subtypes: [
            ShortcutSubtype(id: "work.coding",   label: "编程"),
            ShortcutSubtype(id: "work.meeting",  label: "会议"),
            ShortcutSubtype(id: "work.writing",  label: "写作"),
            ShortcutSubtype(id: "work.design",   label: "设计"),
        ]),
        ShortcutCategory(id: "study", label: "学习", colorHex: "6C5CE7", subtypes: [
            ShortcutSubtype(id: "study.reading",  label: "阅读"),
            ShortcutSubtype(id: "study.course",   label: "课程"),
            ShortcutSubtype(id: "study.notes",    label: "笔记"),
            ShortcutSubtype(id: "study.practice", label: "练习"),
        ]),
        ShortcutCategory(id: "life", label: "生活", colorHex: "24C48E", subtypes: [
            ShortcutSubtype(id: "life.meal",     label: "吃饭"),
            ShortcutSubtype(id: "life.shopping", label: "购物"),
            ShortcutSubtype(id: "life.commute",  label: "通勤"),
            ShortcutSubtype(id: "life.chores",   label: "家务"),
        ]),
        ShortcutCategory(id: "sport", label: "运动", colorHex: "FF6257", subtypes: [
            ShortcutSubtype(id: "sport.gym",     label: "健身"),
            ShortcutSubtype(id: "sport.running", label: "跑步"),
            ShortcutSubtype(id: "sport.yoga",    label: "瑜伽"),
            ShortcutSubtype(id: "sport.ball",    label: "球类"),
        ]),
        ShortcutCategory(id: "rest", label: "休息", colorHex: "FFB02E", subtypes: [
            ShortcutSubtype(id: "rest.sleep",      label: "睡眠"),
            ShortcutSubtype(id: "rest.nap",        label: "小憩"),
            ShortcutSubtype(id: "rest.meditation", label: "冥想"),
            ShortcutSubtype(id: "rest.leisure",    label: "放松"),
        ]),
        ShortcutCategory(id: "fun", label: "娱乐", colorHex: "F642A8", subtypes: [
            ShortcutSubtype(id: "fun.game",   label: "游戏"),
            ShortcutSubtype(id: "fun.music",  label: "音乐"),
            ShortcutSubtype(id: "fun.video",  label: "视频"),
            ShortcutSubtype(id: "fun.social", label: "社交"),
        ]),
    ]

    nonisolated static let defaultTasks: [ShortcutTask] = [
        ShortcutTask(name: "写代码", symbolName: "chevron.left.forwardslash.chevron.right", colorHex: "FF7847"),
        ShortcutTask(name: "阅读", symbolName: "book", colorHex: "FF7847"),
        ShortcutTask(name: "健身", symbolName: "dumbbell", colorHex: "FF7847"),
        ShortcutTask(name: "开会", symbolName: "briefcase", colorHex: "FF7847"),
        ShortcutTask(name: "吃饭", symbolName: "fork.knife", colorHex: "FF7847"),
        ShortcutTask(name: "休息", symbolName: "cup.and.saucer", colorHex: "FF7847")
    ]

    nonisolated static let creationTemplates: [ShortcutTask] = [
        ShortcutTask(name: "写代码", symbolName: "chevron.left.forwardslash.chevron.right", colorHex: "FF7847"),
        ShortcutTask(name: "阅读", symbolName: "book", colorHex: "FF7847"),
        ShortcutTask(name: "健身", symbolName: "dumbbell", colorHex: "FF7847"),
        ShortcutTask(name: "开会", symbolName: "briefcase", colorHex: "FF7847"),
        ShortcutTask(name: "吃饭", symbolName: "fork.knife", colorHex: "FF7847"),
        ShortcutTask(name: "休息", symbolName: "cup.and.saucer", colorHex: "FF7847"),
        ShortcutTask(name: "写日记", symbolName: "pencil", colorHex: "FF7847"),
        ShortcutTask(name: "音乐", symbolName: "music.note", colorHex: "FF7847"),
        ShortcutTask(name: "健康", symbolName: "heart", colorHex: "FF7847"),
        ShortcutTask(name: "拍照", symbolName: "camera", colorHex: "FF7847"),
        ShortcutTask(name: "通勤", symbolName: "car", colorHex: "FF7847"),
        ShortcutTask(name: "购物", symbolName: "cart", colorHex: "FF7847")
    ]

    nonisolated static let iconOptions: [ShortcutTask] = {
        let palette = [
            "6C5CE7", "FF9500", "3F7BF7", "F642A8", "FF6257", "24C48E",
            "FFB02E", "6B7CFF", "22C7BE", "F65BA8", "7AC943", "9D98D9"
        ]
        let items: [(String, String)] = [
            ("睡眠", "moon.stars.fill"),
            ("工作", "briefcase.fill"),
            ("学习", "book.closed.fill"),
            ("娱乐", "gamecontroller.fill"),
            ("生活", "cup.and.saucer.fill"),
            ("运动", "figure.walk"),
            ("吃饭", "fork.knife"),
            ("通勤", "car.fill"),
            ("阅读", "book.fill"),
            ("冥想", "figure.mind.and.body"),
            ("社交", "heart.fill"),
            ("健康", "cross.case.fill"),
            ("购物", "bag.fill"),
            ("户外", "leaf.fill"),
            ("其他", "ellipsis"),
            ("闹钟", "alarm.fill"),
            ("电话", "phone.fill"),
            ("消息", "message.fill"),
            ("邮件", "envelope.fill"),
            ("相机", "camera.fill"),
            ("照片", "photo.fill"),
            ("视频", "video.fill"),
            ("音乐", "music.note"),
            ("播客", "mic.fill"),
            ("地图", "map.fill"),
            ("天气", "cloud.sun.fill"),
            ("日历", "calendar"),
            ("时钟", "clock.fill"),
            ("星标", "star.fill"),
            ("旗帜", "flag.fill"),
            ("定位", "location.fill"),
            ("收藏", "bookmark.fill"),
            ("笔记", "note.text"),
            ("文件", "doc.fill"),
            ("打印", "printer.fill"),
            ("电脑", "desktopcomputer"),
            ("手机", "iphone"),
            ("平板", "ipad.landscape"),
            ("家", "house.fill"),
            ("钥匙", "key.fill"),
            ("钱包", "wallet.pass.fill"),
            ("雨伞", "umbrella.fill"),
            ("雪花", "snowflake"),
            ("火焰", "flame.fill"),
            ("咖啡", "mug.fill"),
            ("啤酒", "mug.fill"),
            ("礼物", "gift.fill"),
            ("购物车", "cart.fill"),
            ("箱包", "suitcase.fill"),
            ("工具", "wrench.and.screwdriver.fill"),
            ("齿轮", "gearshape.fill"),
            ("电池", "battery.100"),
            ("闪电", "bolt.fill"),
            ("盾牌", "shield.fill"),
            ("锁", "lock.fill"),
            ("解锁", "lock.open.fill"),
            ("上箭头", "arrow.up.circle.fill"),
            ("下箭头", "arrow.down.circle.fill"),
            ("左箭头", "arrow.left.circle.fill"),
            ("右箭头", "arrow.right.circle.fill"),
            ("云", "cloud.fill"),
            ("太阳", "sun.max.fill"),
            ("月亮", "moon.fill"),
            ("树叶", "leaf.fill"),
            ("花朵", "flower.fill"),
            ("水滴", "drop.fill"),
            ("波浪", "water.waves"),
            ("山", "mountain.2.fill"),
            ("火车", "train.side.front.car"),
            ("飞机", "airplane"),
            ("自行车", "bicycle"),
            ("跑步", "figure.run"),
            ("健身", "dumbbell.fill"),
            ("心脏", "heart.circle.fill"),
            ("医疗", "cross.case.fill")
        ]

        return items.enumerated().map { index, item in
            ShortcutTask(
                name: item.0,
                symbolName: item.1,
                colorHex: palette[index % palette.count]
            )
        }
    }()

    nonisolated private static let defaultEvents: [ShortcutEvent] = [
        ShortcutEvent(task: defaultTasks[0], kind: .stopped, note: "结束了", createdAt: Calendar.current.date(bySettingHour: 5, minute: 54, second: 0, of: .now) ?? .now),
        ShortcutEvent(task: defaultTasks[1], kind: .note, note: "Import from time tracker #1196 分心...", createdAt: Calendar.current.date(bySettingHour: 8, minute: 1, second: 0, of: .now) ?? .now),
        ShortcutEvent(task: defaultTasks[2], kind: .note, note: "玩手机", createdAt: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now),
        ShortcutEvent(task: defaultTasks[3], kind: .note, note: "吃饭", createdAt: Calendar.current.date(bySettingHour: 12, minute: 5, second: 0, of: .now) ?? .now)
    ]
}

struct RunningShortcutEntry: Hashable {
    var id: Int
    var taskName: String
    var startedAt: Date
}

enum ShortcutAPI {
    static let runningURL = URL(string: "http://100.67.64.11:8081/api/mobile/time-entries/running")!
    static let startURL = URL(string: "http://100.67.64.11:8081/api/mobile/time-entries/start")!
    static let endURL = URL(string: "http://100.67.64.11:8081/api/mobile/time-entries/end")!
    static let categoriesURL = URL(string: "http://100.67.64.11:8081/api/time-categories")!

    static func running() async throws -> RunningShortcutEntry? {
        var request = URLRequest(url: runningURL)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 204 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw apiError(from: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder.timeEntryDecoder.decode(TimeEntryResponse.self, from: data).runningEntry
    }

    static func categories() async throws -> [ShortcutCategory] {
        var request = URLRequest(url: categoriesURL)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ShortcutCategoriesResponse.self, from: data)
        return decoded.categories.map { ShortcutCategory(response: $0) }
    }

    static func start(taskName: String, typeId: String? = nil) async throws {
        let requestBody = StartTimeEntryRequest(
            taskName: taskName,
            typeId: typeId.flatMap { Int($0) },
            startedAt: Date().apiISOString,
            source: "mobile",
            note: nil
        )
        try await post(url: startURL, body: requestBody)
    }

    static func end(note: String) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestBody = EndTimeEntryRequest(note: trimmedNote.isEmpty ? nil : trimmedNote)
        try await post(url: endURL, body: requestBody)
    }

    private static func post<T: Encodable>(url: URL, body: T) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw apiError(from: data, statusCode: httpResponse.statusCode)
        }
    }

    private static func apiError(from data: Data, statusCode: Int) -> Error {
        if let errorResponse = try? JSONDecoder().decode(TimeEntryErrorResponse.self, from: data) {
            return ShortcutAPIError(statusCode: statusCode, message: errorResponse.error)
        }
        return URLError(.badServerResponse)
    }
}

private struct StartTimeEntryRequest: Encodable {
    var taskName: String
    var typeId: Int?
    var startedAt: String?
    var source: String?
    var note: String?
}

private struct ShortcutCategoriesResponse: Decodable {
    var categories: [RemoteCategoryResponse]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decodeIfPresent([RemoteCategoryResponse].self, forKey: .categories) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case categories
    }
}

private struct RemoteCategoryResponse: Decodable {
    var id: String
    var label: String
    var color: String
    var types: [RemoteTypeResponse]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeFlexID(forKey: .id)
        label = (try? c.decode(String.self, forKey: .label))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? id
        color = (try? c.decode(String.self, forKey: .color)) ?? "#8A8F9C"
        types = (try? c.decode([RemoteTypeResponse].self, forKey: .types)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, name, color, types
    }
}

private struct RemoteTypeResponse: Decodable {
    var id: String
    var label: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeFlexID(forKey: .id)
        label = (try? c.decode(String.self, forKey: .label))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? id
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, name
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexID(forKey key: Key) throws -> String {
        if let v = try? decode(String.self, forKey: key) { return v }
        if let v = try? decode(Int.self, forKey: key) { return String(v) }
        if let v = try? decode(Int64.self, forKey: key) { return String(v) }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing id"))
    }
}

private struct EndTimeEntryRequest: Encodable {
    var entryId: Int?
    var endedAt: String?
    var note: String?
}

private struct TimeEntryResponse: Decodable {
    var id: Int
    var taskName: String
    var status: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var source: String?
    var note: String?

    var runningEntry: RunningShortcutEntry {
        RunningShortcutEntry(id: id, taskName: taskName, startedAt: startedAt)
    }
}

private struct TimeEntryErrorResponse: Decodable {
    var success: Bool?
    var error: String
}

private struct ShortcutAPIError: LocalizedError {
    var statusCode: Int
    var message: String

    var errorDescription: String? {
        "\(message) (\(statusCode))"
    }
}

private extension JSONDecoder {
    static var timeEntryDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.parseAPIISODate(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(value)")
        }
        return decoder
    }
}

private extension Date {
    var apiISOString: String {
        ISO8601DateFormatter.apiFormatter.string(from: self)
    }

    static func parseAPIISODate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter.apiFractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter.apiFormatter.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let apiFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let apiFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
