import Foundation
import Combine
import SwiftUI

@MainActor
final class TimeCalendarStore: ObservableObject {
    @Published private(set) var events: [Calendar2Event] = []
    @Published private(set) var categories: [Calendar2Category] = Calendar2Category.fallbackCategories
    @Published var statusMessage = ""
    @Published var isLoading = false

    private var loadedOffsets: Set<Int> = []
    private var hasLoadedRemoteCategories = false

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
                statusMessage = "分类加载失败，已使用默认分类"
            }
        }

        do {
            let newEvents = try await TimeCalendarAPI.events(
                from: Calendar2Format.day(offset: fetchMin),
                to: Calendar2Format.day(offset: fetchMax)
            )
            let fetchedOffsets = Set(fetchMin...fetchMax)
            // 移除本次请求范围内的旧缓存，再合并新数据
            events.removeAll { fetchedOffsets.contains($0.dayOffset) }
            events.append(contentsOf: newEvents)
            loadedOffsets.formUnion(fetchedOffsets)
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

    func category(for id: String) -> Calendar2Category {
        categories.first { $0.id == id } ?? Calendar2Category.fallback(for: id)
    }

    /// 仅在本地构造一条草稿事件，不发送到服务器。
    func makeDraftEvent(dayOffset: Int) -> Calendar2Event {
        let category = categories.first ?? Calendar2Category.fallback(for: "life")
        let type = category.types.first
        let start = Calendar2Format.defaultStartMinute()
        let end = min(start + 30, Calendar2Layout.dayEnd * 60)
        return Calendar2Event(
            id: "",
            dayOffset: dayOffset,
            start: start,
            end: end,
            name: type?.label ?? "新记录",
            category: category.id,
            typeId: type?.id,
            source: "manual",
            note: ""
        )
    }

    /// 点击“保存”后才真正创建：发送到服务器。
    func createEvent(_ event: Calendar2Event) async -> Calendar2Event? {
        do {
            let created = try await TimeCalendarAPI.create(event)
            upsert(created)
            return preferredSegment(from: created, matching: event)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func updateCategory(id: String, categoryId: String) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = "服务器分类未加载成功，不能修改分类"
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        guard let category = categories.first(where: { $0.id == categoryId }) else {
            statusMessage = "服务器分类不存在：\(categoryId)"
            return nil
        }
        event.category = categoryId
        event.typeId = category.types.first?.id
        event.name = category.types.first?.label ?? category.label
        return await update(event)
    }

    func updateName(id: String, name: String, categoryId: String, typeId: String?) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = "服务器分类未加载成功，不能修改名称"
            return nil
        }
        guard categories.contains(where: { $0.id == categoryId }) else {
            statusMessage = "服务器分类不存在：\(categoryId)"
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.name = name
        event.category = categoryId
        event.typeId = typeId
        return await update(event)
    }

    func updateType(id: String, categoryId: String, typeId: String?) async -> Calendar2Event? {
        guard hasLoadedRemoteCategories else {
            statusMessage = "服务器分类未加载成功，不能修改小类"
            return nil
        }
        guard categories.contains(where: { $0.id == categoryId }) else {
            statusMessage = "服务器分类不存在：\(categoryId)"
            return nil
        }
        guard var event = events.first(where: { $0.id == id }) else { return nil }
        event.category = categoryId
        event.typeId = typeId
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
        event.start = start
        event.end = end
        return await update(event)
    }

    func delete(id: String) async -> Bool {
        guard let event = events.first(where: { $0.id == id }) else { return false }
        do {
            try await TimeCalendarAPI.delete(id: event.sourceEventId)
            events.removeAll { $0.sourceEventId == event.sourceEventId }
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func update(_ event: Calendar2Event) async -> Calendar2Event? {
        do {
            let updated = try await TimeCalendarAPI.update(event)
            upsert(updated)
            return preferredSegment(from: updated, matching: event)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func upsert(_ newEvents: [Calendar2Event]) {
        guard let sourceEventId = newEvents.first?.sourceEventId else { return }
        events.removeAll { $0.sourceEventId == sourceEventId }
        events.append(contentsOf: newEvents)
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
            return "接口数据格式不匹配：\(decodingError.readableDescription)"
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
    #if DEBUG
    static let baseURL = URL(string: "http://192.168.1.155:8081/api")!
    #else
    static let baseURL = URL(string: "http://100.67.64.11:8081/api")!
    #endif

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

    private static func send<T: Decodable, Body: Encodable>(_ type: T.Type, url: URL, method: String, body: Body? = Optional<String>.none) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.timeCalendarEncoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TimeCalendarAPIError(statusCode: httpResponse.statusCode, data: data)
        }
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

struct TimeCategoryResponse: Decodable {
    var id: String
    var label: String
    var color: String
    var types: [TimeCategoryTypeResponse]

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case name
        case title
        case color
        case types
        case subs
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        label = try container.decodeFirstString(keys: [.label, .name, .title]) ?? id
        color = try container.decodeFirstString(keys: [.color]) ?? "#8A8F9C"
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

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case name
        case title
        case color
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            id = value
            label = value
            color = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        label = try container.decodeFirstString(keys: [.label, .name, .title]) ?? id
        color = try container.decodeFirstString(keys: [.color])
    }
}

struct TimeEventResponse: Decodable {
    var id: String
    var name: String
    var categoryId: String
    var typeId: String?
    var startedAt: Date
    var endedAt: Date?
    var source: String?
    var note: String?

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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(for: .id)
        name = try container.decodeFirstString(keys: [.name, .taskName, .task_name]) ?? "未命名"
        categoryId = try container.decodeFirstString(keys: [.categoryId, .category_id, .category]) ?? "rest"
        typeId = try container.decodeFirstString(keys: [.typeId, .type_id])
        startedAt = try container.decodeFirstDate(keys: [.startedAt, .started_at, .startTime, .start_time])
        endedAt = try container.decodeFirstOptionalDate(keys: [.endedAt, .ended_at, .endTime, .end_time])
        source = try container.decodeFirstString(keys: [.source])
        note = try container.decodeFirstString(keys: [.note])
    }
}

private struct TimeEventRequest: Encodable {
    var categoryId: String
    var typeId: String?
    var name: String
    var startedAt: Date
    var endedAt: Date
    var note: String?

    init(event: Calendar2Event) {
        categoryId = event.category
        typeId = event.typeId
        name = event.name
        startedAt = event.absoluteStartedAt
        endedAt = event.absoluteEndedAt ?? Calendar2Format.date(dayOffset: event.dayOffset, minute: event.end)
        note = event.note
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
        return "日历接口请求失败 (\(statusCode))"
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
            return "缺少字段 \(key.stringValue)；路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let context):
            return "字段类型不匹配；路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context):
            return "字段为空；路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))"
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
