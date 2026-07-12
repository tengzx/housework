import Foundation
import Combine
import SwiftUI

@MainActor
final class TimeCalendarStore: ObservableObject {
    @Published private(set) var events: [Calendar2Event] = []
    @Published private(set) var categories: [Calendar2Category] = Calendar2Category.fallbackCategories
    @Published private(set) var mobileAppEvents: [Calendar2Event] = []
    @Published var statusMessage = ""
    @Published var isLoading = false

    private var loadedOffsets: Set<Int> = []
    private var hasLoadedRemoteCategories = false
    private var loadedMobileAppOffsets: Set<Int> = []

    func loadVisibleRange(offsets: [Int], force: Bool = false) async {
        guard let minOffset = offsets.min(), let maxOffset = offsets.max() else { return }

        let requestedOffsets = Set(minOffset...maxOffset)
        let missingOffsets = force ? requestedOffsets : requestedOffsets.subtracting(loadedOffsets)
        guard !missingOffsets.isEmpty else { return }

        let fetchMin = missingOffsets.min()!
        let fetchMax = missingOffsets.max()!

        isLoading = true
        defer {
            isLoading = false
        }
        statusMessage = ""

        if !hasLoadedRemoteCategories || force {
            do {
                categories = try await TimeCalendarAPI.categories()
                hasLoadedRemoteCategories = !categories.isEmpty
            } catch {
                guard !Self.isCancellation(error) else { return }
                categories = Calendar2Category.fallbackCategories
                hasLoadedRemoteCategories = false
                statusMessage = SharedL10n.tr("time.calendar.categories_load_failed")
            }
        }

        do {
            let newEvents = try await TimeCalendarAPI.events(
                from: Calendar2Format.day(offset: fetchMin),
                to: Calendar2Format.day(offset: fetchMax)
            )
            let fetchedOffsets = Set(fetchMin...fetchMax)
            // 移除旧缓存，但保留乐观插入的 pending 事件
            events.removeAll { fetchedOffsets.contains($0.dayOffset) && !$0.isPending }
            events.append(contentsOf: newEvents)
            // 今天(0)和昨天(-1)不缓存，保证跨设备新事件随时可见
            loadedOffsets.formUnion(fetchedOffsets.filter { $0 < -1 })
        } catch {
            guard !Self.isCancellation(error) else { return }
            statusMessage = readableMessage(for: error)
        }
    }

    func refresh(offsets: [Int]) async {
        loadedOffsets = []
        hasLoadedRemoteCategories = false
        await loadVisibleRange(offsets: offsets, force: true)
    }

    func loadMobileAppEvents(offsets: [Int]) async {
        guard let minOffset = offsets.min(), let maxOffset = offsets.max() else { return }
        let requestedOffsets = Set(minOffset...maxOffset)
        let missingOffsets = requestedOffsets.subtracting(loadedMobileAppOffsets)
        guard !missingOffsets.isEmpty else { return }

        let fetchMin = missingOffsets.min()!
        let fetchMax = missingOffsets.max()!

        do {
            let newEvents = try await TimeCalendarAPI.mobileAppEvents(
                from: Calendar2Format.day(offset: fetchMin),
                to: Calendar2Format.day(offset: fetchMax)
            )
            let fetchedOffsets = Set(fetchMin...fetchMax)
            mobileAppEvents.removeAll { fetchedOffsets.contains($0.dayOffset) }
            mobileAppEvents.append(contentsOf: newEvents)
            loadedMobileAppOffsets.formUnion(fetchedOffsets)
        } catch {
            guard !Self.isCancellation(error) else { return }
        }
    }

    func clearMobileAppEvents() {
        mobileAppEvents = []
        loadedMobileAppOffsets = []
    }

    func category(for id: String) -> Calendar2Category {
        categories.first { $0.id == id } ?? Calendar2Category.fallback(for: id)
    }

    /// 仅在本地构造一条草稿事件，不发送到服务器。
    func makeDraftEvent(dayOffset: Int, startMinute: Int? = nil, endMinute: Int? = nil) -> Calendar2Event {
        let category = categories.first ?? Calendar2Category.fallback(for: "life")
        let type = category.types.first
        let start = startMinute ?? Calendar2Format.defaultStartMinute()
        let end = min(endMinute ?? (start + 30), Calendar2Layout.dayEnd * 60)
        return Calendar2Event(
            id: "",
            dayOffset: dayOffset,
            start: start,
            end: end,
            name: type?.label ?? SharedL10n.tr("time.calendar.new_entry"),
            category: category.id,
            typeId: type?.id,
            source: "manual",
            note: ""
        )
    }

    /// 点击”保存”后才真正创建：先乐观插入本地，服务器确认后替换，失败则撤销。
    func createEvent(_ event: Calendar2Event) async -> Calendar2Event? {
        let tempId = "pending_\(UUID().uuidString)"
        let optimistic = Calendar2Event(
            id: tempId,
            sourceEventId: tempId,
            absoluteStartedAt: event.absoluteStartedAt,
            absoluteEndedAt: event.absoluteEndedAt,
            dayOffset: event.dayOffset,
            start: event.start,
            end: event.end,
            name: event.name,
            category: event.category,
            typeId: event.typeId,
            source: event.source,
            note: event.note,
            goalId: event.goalId,
            isPending: true
        )
        events.append(optimistic)
        do {
            let created = try await TimeCalendarAPI.create(event)
            events.removeAll { $0.id == tempId }
            upsert(created)
            return preferredSegment(from: created, matching: event)
        } catch {
            events.removeAll { $0.id == tempId }
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func createNaturalLanguageEvent(text: String, dayOffset: Int, note: String? = nil) async -> Calendar2Event? {
        do {
            let created = try await TimeCalendarAPI.createNaturalLanguage(text: text, dayOffset: dayOffset, note: note)
            upsert(created)
            return created.first(where: { $0.dayOffset == dayOffset }) ?? created.first
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func updateCategory(id: String, categoryId: String) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = SharedL10n.tr("time.calendar.server_categories_unavailable_update_category")
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        guard let category = categories.first(where: { $0.id == categoryId }) else {
            statusMessage = SharedL10n.tr("time.calendar.server_category_missing", categoryId)
            return nil
        }
        event.category = categoryId
        event.typeId = category.types.first?.id
        event.name = category.types.first?.label ?? category.label
        event.colorHex = nil // 清掉旧的服务端颜色，先按新分类着色，服务器确认后再回填
        return await update(event)
    }

    func updateName(id: String, name: String, categoryId: String, typeId: String?) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = SharedL10n.tr("time.calendar.server_categories_unavailable_update_name")
            return nil
        }
        guard categories.contains(where: { $0.id == categoryId }) else {
            statusMessage = SharedL10n.tr("time.calendar.server_category_missing", categoryId)
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.name = name
        event.category = categoryId
        event.typeId = typeId
        event.colorHex = nil
        return await update(event)
    }

    func updateType(id: String, categoryId: String, typeId: String?) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = SharedL10n.tr("time.calendar.server_categories_unavailable_update_type")
            return nil
        }
        guard categories.contains(where: { $0.id == categoryId }) else {
            statusMessage = SharedL10n.tr("time.calendar.server_category_missing", categoryId)
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.category = categoryId
        event.typeId = typeId
        event.colorHex = nil
        return await update(event)
    }

    func updateTime(id: String, start: Int, end: Int) async -> Calendar2Event? {
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.start = start
        event.end = end
        return await update(event)
    }

    func updateAll(id: String, name: String, categoryId: String, typeId: String?, start: Int, end: Int) async -> Calendar2Event? {
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.name = name
        event.category = categoryId
        event.typeId = typeId
        event.colorHex = nil
        event.start = start
        event.end = end
        return await update(event)
    }

    func updateEvent(_ event: Calendar2Event) async -> Calendar2Event? {
        return await update(event)
    }

    func delete(id: String) async -> Bool {
        guard let event = events.first(where: { $0.id == id }) else { return false }
        // 乐观删除：先从本地移除，失败时恢复
        let removed = events.filter { $0.sourceEventId == event.sourceEventId }
        events.removeAll { $0.sourceEventId == event.sourceEventId }
        do {
            try await TimeCalendarAPI.delete(id: event.sourceEventId)
            return true
        } catch {
            events.append(contentsOf: removed)
            statusMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Category CRUD

    func createCategory(name: String, hexColor: String, loadKind: LoadKind? = nil) async throws -> Calendar2Category {
        let category = try await TimeCalendarAPI.createCategory(name: name, color: hexColor, loadKind: loadKind)
        categories.append(category)
        return category
    }

    func updateCategory(id: String, name: String, hexColor: String, loadKind: LoadKind?) async throws {
        let updated = try await TimeCalendarAPI.updateCategory(id: id, name: name, color: hexColor, loadKind: loadKind)
        if let idx = categories.firstIndex(where: { $0.id == id }) {
            categories[idx] = updated
        }
    }

    func deleteCategory(id: String) async throws {
        try await TimeCalendarAPI.deleteCategory(id: id)
        categories.removeAll { $0.id == id }
    }

    func createType(categoryId: String, name: String, tracksFocus: Bool = false, loadKindOverride: LoadKind? = nil) async throws -> Calendar2CategoryType {
        let newType = try await TimeCalendarAPI.createType(categoryId: categoryId, name: name, tracksFocus: tracksFocus, loadKindOverride: loadKindOverride)
        if let idx = categories.firstIndex(where: { $0.id == categoryId }) {
            let cat = categories[idx]
            categories[idx] = Calendar2Category(id: cat.id, label: cat.label, color: cat.color, icon: cat.icon, loadKind: cat.loadKind, types: cat.types + [newType])
        }
        return newType
    }

    func updateType(id: String, name: String, tracksFocus: Bool, loadKindOverride: LoadKind?) async throws {
        let updated = try await TimeCalendarAPI.updateType(id: id, name: name, tracksFocus: tracksFocus, loadKindOverride: loadKindOverride)
        for (catIdx, cat) in categories.enumerated() {
            if let typeIdx = cat.types.firstIndex(where: { $0.id == id }) {
                var types = cat.types
                types[typeIdx] = updated
                categories[catIdx] = Calendar2Category(id: cat.id, label: cat.label, color: cat.color, icon: cat.icon, loadKind: cat.loadKind, types: types)
                break
            }
        }
    }

    func deleteType(id: String) async throws {
        try await TimeCalendarAPI.deleteType(id: id)
        for (catIdx, cat) in categories.enumerated() {
            if cat.types.contains(where: { $0.id == id }) {
                categories[catIdx] = Calendar2Category(id: cat.id, label: cat.label, color: cat.color, icon: cat.icon, loadKind: cat.loadKind, types: cat.types.filter { $0.id != id })
                break
            }
        }
    }

    func reloadCategories() async throws {
        categories = try await TimeCalendarAPI.categories()
        hasLoadedRemoteCategories = !categories.isEmpty
    }

    private func update(_ event: Calendar2Event) async -> Calendar2Event? {
        // 乐观更新：先改本地，服务器失败时回滚
        let original = events.filter { $0.sourceEventId == event.sourceEventId }
        upsertOptimistic(event)
        do {
            let updated = try await TimeCalendarAPI.update(event)
            upsert(updated)
            return preferredSegment(from: updated, matching: event)
        } catch {
            // 回滚到修改前的状态
            events.removeAll { $0.sourceEventId == event.sourceEventId }
            events.append(contentsOf: original)
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func upsert(_ newEvents: [Calendar2Event]) {
        guard let sourceEventId = newEvents.first?.sourceEventId else { return }
        events.removeAll { $0.sourceEventId == sourceEventId }
        events.append(contentsOf: newEvents)
    }

    private func upsertOptimistic(_ event: Calendar2Event) {
        // 直接替换同 sourceEventId 的所有段，服务器确认后再修正分段
        events.removeAll { $0.sourceEventId == event.sourceEventId }
        events.append(event)
    }

    private func preferredSegment(from events: [Calendar2Event], matching reference: Calendar2Event) -> Calendar2Event? {
        events.first {
            $0.dayOffset == reference.dayOffset &&
            $0.start == reference.start &&
            $0.end == reference.end
        } ?? events.first(where: { $0.dayOffset == reference.dayOffset }) ?? events.first
    }

    private func readableMessage(for error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return SharedL10n.tr("time.calendar.response_mismatch", decodingError.readableDescription)
        }
        return error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}

enum TimeCalendarAPI {
    static let baseURL = AppEnvironment.apiBaseURL

    static func events(from: Date, to: Date) async throws -> [Calendar2Event] {
        var components = URLComponents(url: baseURL.appendingPathComponent("time-events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "from", value: Calendar2Format.apiDate(from)),
            URLQueryItem(name: "to", value: Calendar2Format.apiDate(to))
        ]
        let response = try await send(FlexibleEventsResponse.self, url: components.url!, method: "GET")
        return response.events.flatMap { Calendar2Event.segments(response: $0) }
    }

    static func categories() async throws -> [Calendar2Category] {
        let response = try await send(FlexibleCategoriesResponse.self, url: baseURL.appendingPathComponent("time-categories"), method: "GET")
        return response.categories.map(Calendar2Category.init(response:))
    }

    static func create(_ event: Calendar2Event) async throws -> [Calendar2Event] {
        let response = try await send(
            FlexibleEventEnvelope.self,
            url: baseURL.appendingPathComponent("time-events"),
            method: "POST",
            body: TimeEventRequest(event: event)
        )
        return Calendar2Event.segments(response: response.event)
    }

    static func createNaturalLanguage(text: String, dayOffset: Int, note: String?) async throws -> [Calendar2Event] {
        let response = try await send(
            FlexibleEventEnvelope.self,
            url: baseURL.appendingPathComponent("time-events").appendingPathComponent("natural-language"),
            method: "POST",
            body: NaturalLanguageTimeEventRequest(
                text: text,
                date: Calendar2Format.apiDate(Calendar2Format.day(offset: dayOffset)),
                note: note
            )
        )
        return Calendar2Event.segments(response: response.event)
    }

    static func update(_ event: Calendar2Event) async throws -> [Calendar2Event] {
        let response = try await send(
            FlexibleEventEnvelope.self,
            url: baseURL.appendingPathComponent("time-events").appendingPathComponent(event.sourceEventId),
            method: "PATCH",
            body: TimeEventRequest(event: event)
        )
        return Calendar2Event.segments(response: response.event)
    }

    static func delete(id: String) async throws {
        _ = try await send(DeleteTimeEventResponse.self, url: baseURL.appendingPathComponent("time-events").appendingPathComponent(id), method: "DELETE")
    }

    static func createCategory(name: String, color: String?, loadKind: LoadKind?) async throws -> Calendar2Category {
        let response = try await send(
            TimeCategoryEnvelope.self,
            url: baseURL.appendingPathComponent("time-categories"),
            method: "POST",
            body: TimeCategoryRequest(name: name, color: color, loadKind: loadKind?.rawValue)
        )
        return Calendar2Category(response: response.category)
    }

    static func updateCategory(id: String, name: String, color: String?, loadKind: LoadKind?) async throws -> Calendar2Category {
        let response = try await send(
            TimeCategoryEnvelope.self,
            url: baseURL.appendingPathComponent("time-categories").appendingPathComponent(id),
            method: "PATCH",
            body: TimeCategoryRequest(name: name, color: color, loadKind: loadKind?.rawValue)
        )
        return Calendar2Category(response: response.category)
    }

    static func deleteCategory(id: String) async throws {
        _ = try await send(
            DeleteTimeEventResponse.self,
            url: baseURL.appendingPathComponent("time-categories").appendingPathComponent(id),
            method: "DELETE"
        )
    }

    static func createType(categoryId: String, name: String, tracksFocus: Bool = false, loadKindOverride: LoadKind?) async throws -> Calendar2CategoryType {
        let response = try await send(
            TimeTypeEnvelope.self,
            url: baseURL.appendingPathComponent("time-categories").appendingPathComponent(categoryId).appendingPathComponent("types"),
            method: "POST",
            body: TimeTypeRequest(name: name, tracksFocus: tracksFocus, loadKindOverride: loadKindOverride?.rawValue)
        )
        let t = response.eventType
        return Calendar2CategoryType(id: t.id, label: t.label, color: t.color.map { Color(hex: $0) }, icon: t.icon, loadKindOverride: t.loadKindOverride.flatMap(LoadKind.init(rawValue:)), tracksFocus: t.tracksFocus ?? false)
    }

    static func updateType(id: String, name: String, tracksFocus: Bool, loadKindOverride: LoadKind?) async throws -> Calendar2CategoryType {
        let response = try await send(
            TimeTypeEnvelope.self,
            url: baseURL.appendingPathComponent("time-types").appendingPathComponent(id),
            method: "PATCH",
            body: TimeTypeRequest(name: name, tracksFocus: tracksFocus, loadKindOverride: loadKindOverride?.rawValue, clearLoadKindOverride: loadKindOverride == nil)
        )
        let t = response.eventType
        return Calendar2CategoryType(id: t.id, label: t.label, color: t.color.map { Color(hex: $0) }, icon: t.icon, loadKindOverride: t.loadKindOverride.flatMap(LoadKind.init(rawValue:)), tracksFocus: t.tracksFocus ?? false)
    }

    static func deleteType(id: String) async throws {
        _ = try await send(
            DeleteTimeEventResponse.self,
            url: baseURL.appendingPathComponent("time-types").appendingPathComponent(id),
            method: "DELETE"
        )
    }

    static func mobileAppEvents(from: Date, to: Date) async throws -> [Calendar2Event] {
        var components = URLComponents(url: baseURL.appendingPathComponent("mobile-app-events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "from", value: Calendar2Format.apiDate(from)),
            URLQueryItem(name: "to", value: Calendar2Format.apiDate(to))
        ]
        let response = try await send(MobileAppEventsResponse.self, url: components.url!, method: "GET")
        return response.events.flatMap {
            Calendar2Event.mobileAppSegments(
                id: $0.id, name: $0.name, categoryId: $0.categoryId, typeId: $0.typeId,
                startedAt: $0.startedAt, endedAt: $0.endedAt, source: $0.source
            )
        }
    }

    private static func send<T: Decodable, Body: Encodable>(_ type: T.Type, url: URL, method: String, body: Body? = Optional<String>.none) async throws -> T {
        let httpMethod = HTTPMethod(rawValue: method) ?? .get
        let response: HTTPClientResponse
        do {
            response = try await HTTPClient.shared.data(
                url: url,
                method: httpMethod,
                body: body,
                encoder: JSONEncoder.timeCalendarEncoder
            )
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                throw TimeCalendarAPIError(statusCode: statusCode, data: data)
            }
            throw error
        }
        let data = response.data
        if data.isEmpty, T.self == DeleteTimeEventResponse.self {
            return DeleteTimeEventResponse(ok: true) as! T
        }
        return try JSONDecoder.timeCalendarDecoder.decode(T.self, from: data)
    }
}

private struct FlexibleEventsResponse: Decodable {
    var events: [TimeEventResponse]

    init(from decoder: Decoder) throws {
        if let array = try? [TimeEventResponse](from: decoder) {
            events = array
            return
        }

        let container = try decoder.container(keyedBy: FlexibleEnvelopeKeys.self)
        if let value = try container.decodeIfPresent([TimeEventResponse].self, forKey: .events) {
            events = value
        } else if let value = try container.decodeIfPresent([TimeEventResponse].self, forKey: .data) {
            events = value
        } else if let value = try container.decodeIfPresent([TimeEventResponse].self, forKey: .items) {
            events = value
        } else {
            events = []
        }
    }
}

private struct FlexibleEventEnvelope: Decodable {
    var event: TimeEventResponse

    init(from decoder: Decoder) throws {
        if let direct = try? TimeEventResponse(from: decoder) {
            event = direct
            return
        }

        let container = try decoder.container(keyedBy: FlexibleEnvelopeKeys.self)
        if let value = try container.decodeIfPresent(TimeEventResponse.self, forKey: .event) {
            event = value
        } else if let value = try container.decodeIfPresent(TimeEventResponse.self, forKey: .data) {
            event = value
        } else {
            throw DecodingError.keyNotFound(
                FlexibleEnvelopeKeys.event,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing event/data")
            )
        }
    }
}

private struct FlexibleCategoriesResponse: Decodable {
    var categories: [TimeCategoryResponse]

    init(from decoder: Decoder) throws {
        if let array = try? [TimeCategoryResponse](from: decoder) {
            categories = array
            return
        }

        let container = try decoder.container(keyedBy: FlexibleEnvelopeKeys.self)
        if let value = try container.decodeIfPresent([TimeCategoryResponse].self, forKey: .categories) {
            categories = value
        } else if let value = try container.decodeIfPresent([TimeCategoryResponse].self, forKey: .data) {
            categories = value
        } else if let value = try container.decodeIfPresent([TimeCategoryResponse].self, forKey: .items) {
            categories = value
        } else {
            categories = []
        }
    }
}

private enum FlexibleEnvelopeKeys: String, CodingKey {
    case events
    case event
    case categories
    case data
    case items
}

private struct DeleteTimeEventResponse: Decodable {
    var ok: Bool
}

private struct TimeCategoryRequest: Encodable {
    var name: String?
    var color: String?
    var loadKind: String? = nil
}

private struct TimeTypeRequest: Encodable {
    var name: String?
    var tracksFocus: Bool?
    var loadKindOverride: String? = nil
    var clearLoadKindOverride: Bool? = nil
}

private struct TimeCategoryEnvelope: Decodable {
    var category: TimeCategoryResponse
}

private struct TimeTypeEnvelope: Decodable {
    var eventType: TimeCategoryTypeResponse
    enum CodingKeys: String, CodingKey {
        case eventType = "type"
    }
}

struct TimeCategoryResponse: Decodable {
    var id: String
    var label: String
    var color: String
    var icon: String?
    var loadKind: String?
    var types: [TimeCategoryTypeResponse]

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case name
        case title
        case color
        case icon
        case loadKind
        case types
        case subs
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        label = try container.decodeFirstString(keys: [.label, .name, .title]) ?? id
        color = try container.decodeFirstString(keys: [.color]) ?? "#8A8F9C"
        icon = try container.decodeFirstString(keys: [.icon])
        loadKind = try container.decodeFirstString(keys: [.loadKind])
        types = (
            try container.decodeIfPresent([TimeCategoryTypeResponse].self, forKey: .types)
            ?? container.decodeIfPresent([TimeCategoryTypeResponse].self, forKey: .subs)
            ?? container.decodeIfPresent([TimeCategoryTypeResponse].self, forKey: .children)
            ?? []
        )
    }
}

struct TimeCategoryTypeResponse: Decodable {
    var id: String
    var label: String
    var color: String?
    var icon: String?
    var tracksFocus: Bool?
    var loadKindOverride: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case name
        case title
        case color
        case icon
        case tracksFocus
        case loadKindOverride
        case tracksFocusSnake = "tracks_focus"
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            id = value
            label = value
            color = nil
            icon = nil
            tracksFocus = nil
            loadKindOverride = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        label = try container.decodeFirstString(keys: [.label, .name, .title]) ?? id
        color = try container.decodeFirstString(keys: [.color])
        icon = try container.decodeFirstString(keys: [.icon])
        tracksFocus = try container.decodeIfPresent(Bool.self, forKey: .tracksFocus)
            ?? container.decodeIfPresent(Bool.self, forKey: .tracksFocusSnake)
        loadKindOverride = try container.decodeFirstString(keys: [.loadKindOverride])
    }
}

struct TimeEventResponse: Decodable {
    var id: String
    var name: String
    var categoryId: String
    var typeId: String?
    var categoryName: String?
    var typeName: String?
    var categoryColor: String?
    var typeColor: String?
    var startedAt: Date
    var endedAt: Date?
    var source: String?
    var note: String?
    /// 事件归属的目标/项目（快照 id），用于按目标统计时长。
    var goalId: Int?

    /// 服务端下发的分段颜色：优先使用小类颜色，其次大类颜色。
    var resolvedColor: String? { typeColor ?? categoryColor }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case taskName
        case task_name
        case categoryId
        case category_id
        case category
        case typeId
        case type_id
        case categoryName
        case category_name
        case typeName
        case type_name
        case categoryColor
        case category_color
        case typeColor
        case type_color
        case startedAt
        case started_at
        case startTime
        case start_time
        case endedAt
        case ended_at
        case endTime
        case end_time
        case source
        case note
        case goalId
        case goal_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        name = try container.decodeFirstString(keys: [.name, .taskName, .task_name]) ?? SharedL10n.tr("record.fallback.unnamed")
        categoryId = try container.decodeFirstString(keys: [.categoryId, .category_id, .category]) ?? "rest"
        typeId = try container.decodeFirstString(keys: [.typeId, .type_id])
        categoryName = try container.decodeFirstString(keys: [.categoryName, .category_name])
        typeName = try container.decodeFirstString(keys: [.typeName, .type_name])
        categoryColor = try container.decodeFirstString(keys: [.categoryColor, .category_color])
        typeColor = try container.decodeFirstString(keys: [.typeColor, .type_color])
        startedAt = try container.decodeFirstDate(keys: [.startedAt, .started_at, .startTime, .start_time])
        endedAt = try container.decodeFirstOptionalDate(keys: [.endedAt, .ended_at, .endTime, .end_time])
        source = try container.decodeFirstString(keys: [.source])
        note = try container.decodeFirstString(keys: [.note])
        goalId = try container.decodeFirstString(keys: [.goalId, .goal_id]).flatMap(Int.init)
    }
}

private struct TimeEventRequest: Encodable {
    var categoryId: String
    var typeId: String?
    var name: String
    var startedAt: Date
    var endedAt: Date
    var note: String?
    var goalId: Int?
    /// PATCH semantics: goalId set → 归属该目标; clearGoal → 移除归属. The local
    /// event carries the server's goalId, so a nil here really means "no goal".
    var clearGoal: Bool?

    init(event: Calendar2Event) {
        categoryId = event.category
        typeId = event.typeId
        name = event.name
        startedAt = event.absoluteStartedAt
        endedAt = event.absoluteEndedAt ?? Calendar2Format.date(dayOffset: event.dayOffset, minute: event.end)
        note = event.note
        goalId = event.goalId
        clearGoal = event.goalId == nil ? true : nil
    }
}

private struct NaturalLanguageTimeEventRequest: Encodable {
    var text: String
    var date: String
    var note: String?
}

struct MobileAppEventResponse: Decodable {
    var id: String
    var name: String
    var categoryId: String
    var typeId: String?
    var startedAt: Date
    var endedAt: Date?
    var source: String?
    var status: String

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryId, typeId, startedAt, endedAt, source, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? SharedL10n.tr("record.fallback.unnamed")
        categoryId = (try? container.decode(String.self, forKey: .categoryId)) ?? "mobile-app-sessions"
        typeId = try? container.decode(String.self, forKey: .typeId)
        startedAt = try container.decodeFirstDate(keys: [.startedAt])
        endedAt = try container.decodeFirstOptionalDate(keys: [.endedAt])
        source = try? container.decode(String.self, forKey: .source)
        status = (try? container.decode(String.self, forKey: .status)) ?? "DONE"
    }
}

private struct MobileAppEventsResponse: Decodable {
    var events: [MobileAppEventResponse]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleEnvelopeKeys.self)
        events = (try container.decodeIfPresent([MobileAppEventResponse].self, forKey: .events)) ?? []
    }
}

private struct TimeCalendarAPIError: LocalizedError {
    var statusCode: Int
    var data: Data

    var errorDescription: String? {
        if let response = try? JSONDecoder().decode(TimeCalendarErrorResponse.self, from: data) {
            return "\(response.error.message) (\(statusCode))"
        }
        if let response = try? JSONDecoder().decode(ShortcutStyleErrorResponse.self, from: data) {
            return "\(response.error) (\(statusCode))"
        }
        return SharedL10n.tr("time.calendar.request_failed", statusCode)
    }
}

private struct TimeCalendarErrorResponse: Decodable {
    var error: Detail

    struct Detail: Decodable {
        var code: String?
        var message: String
    }
}

private struct ShortcutStyleErrorResponse: Decodable {
    var error: String
}

private extension DecodingError {
    var readableDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            return SharedL10n.tr("time.calendar.decoding.key_not_found", key.stringValue, context.codingPath.map(\.stringValue).joined(separator: "."))
        case .typeMismatch(_, let context):
            return SharedL10n.tr("time.calendar.decoding.type_mismatch", context.codingPath.map(\.stringValue).joined(separator: "."))
        case .valueNotFound(_, let context):
            return SharedL10n.tr("time.calendar.decoding.value_not_found", context.codingPath.map(\.stringValue).joined(separator: "."))
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return localizedDescription
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(for key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing \(key.stringValue)")
        )
    }

    func decodeFirstString(keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try? decode(String.self, forKey: key), !value.isEmpty {
                return value
            }
            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? decode(Int64.self, forKey: key) {
                return String(value)
            }
        }
        return nil
    }

    func decodeFirstDate(keys: [Key]) throws -> Date {
        for key in keys {
            if let value = try? decode(Date.self, forKey: key) {
                return value
            }
            if let value = try? decode(String.self, forKey: key),
               let date = try? Calendar2Format.parseAPIDate(value) {
                return date
            }
        }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing date")
        )
    }

    func decodeFirstOptionalDate(keys: [Key]) throws -> Date? {
        for key in keys {
            if let value = try? decodeIfPresent(Date.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let date = try? Calendar2Format.parseAPIDate(value) {
                return date
            }
        }
        return nil
    }
}

extension JSONDecoder {
    static var timeCalendarDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            return try Calendar2Format.parseAPIDate(value)
        }
        return decoder
    }
}

extension JSONEncoder {
    static var timeCalendarEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Calendar2Format.apiDateTime(date))
        }
        return encoder
    }
}
