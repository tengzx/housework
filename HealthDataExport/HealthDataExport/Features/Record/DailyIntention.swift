import Combine
import Foundation
import SwiftUI

/// A "today's intention": something the user plans to do today. Only a name —
/// no type, duration or icon. Scoped to a single day; unfinished intentions
/// simply don't show up the next day.
struct DailyIntentionItem: Codable, Identifiable, Hashable {
    let id: UUID
    /// Backend `daily_intentions.id`. Nil while an optimistically-created
    /// intention is still waiting for its POST to land.
    var remoteId: Int?
    var name: String
    var completedAt: Date?
    var sortOrder: Int

    var isCompleted: Bool { completedAt != nil }

    init(id: UUID = UUID(), remoteId: Int? = nil, name: String, completedAt: Date? = nil, sortOrder: Int = 0) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.completedAt = completedAt
        self.sortOrder = sortOrder
    }
}

/// A queued backend intention operation, persisted so it survives relaunch and
/// is retried until it lands (same optimistic pattern as the shortcut queues).
struct DailyIntentionOperation: Codable, Identifiable {
    enum Kind: String, Codable {
        case create
        case setCompleted
        case delete
    }

    let id: UUID
    let kind: Kind
    /// Local `DailyIntentionItem.id` this operation targets.
    let localId: UUID
    /// Known backend id at enqueue time (set for mutations of synced items).
    var remoteId: Int?
    var name: String?
    var completed: Bool?
    /// "yyyy-MM-dd" the create belongs to, captured at enqueue time.
    var dateKey: String?

    init(id: UUID = UUID(), kind: Kind, localId: UUID, remoteId: Int? = nil, name: String? = nil, completed: Bool? = nil, dateKey: String? = nil) {
        self.id = id
        self.kind = kind
        self.localId = localId
        self.remoteId = remoteId
        self.name = name
        self.completed = completed
        self.dateKey = dateKey
    }
}

@MainActor
final class DailyIntentionStore: ObservableObject {
    static let shared = DailyIntentionStore()

    @Published private(set) var items: [DailyIntentionItem] = []
    /// Intention whose 开始 launched the currently-running timer; completed when
    /// the timer is stopped.
    @Published private(set) var activeIntentionId: UUID?

    private let itemsKey = "dailyIntentions.items"
    private let dateKey = "dailyIntentions.date"
    private let pendingKey = "dailyIntentions.pendingOps"
    private let remoteIdsKey = "dailyIntentions.remoteIds"
    private let activeIdKey = "dailyIntentions.activeId"
    private let userDefaults: UserDefaults

    private var pendingOps: [DailyIntentionOperation] = []
    private var isFlushing = false
    /// Maps a local item id to its server id once a create lands, so a later
    /// patch/delete can resolve the id even after the item left `items`.
    private var remoteIds: [UUID: Int] = [:]
    /// The local day the persisted items belong to.
    private var storedDay: String

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.storedDay = userDefaults.string(forKey: dateKey) ?? Self.todayKey
        self.items = Self.load([DailyIntentionItem].self, key: itemsKey, from: userDefaults) ?? []
        self.pendingOps = Self.load([DailyIntentionOperation].self, key: pendingKey, from: userDefaults) ?? []
        self.remoteIds = Self.load([String: Int].self, key: remoteIdsKey, from: userDefaults)
            .map { Dictionary(uniqueKeysWithValues: $0.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } }) }
            ?? [:]
        self.activeIntentionId = userDefaults.string(forKey: activeIdKey).flatMap(UUID.init(uuidString:))
        rolloverIfNeeded()
        if !pendingOps.isEmpty {
            Task { await flush() }
        }
    }

    /// The running intention pinned first, then the rest of the incomplete ones
    /// (in user order), completed last (in completion order).
    var sortedItems: [DailyIntentionItem] {
        let open = items.filter { !$0.isCompleted }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let done = items.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let active = open.filter { $0.id == activeIntentionId }
        let rest = open.filter { $0.id != activeIntentionId }
        return active + rest + done
    }

    func add(name: String) {
        rolloverIfNeeded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = DailyIntentionItem(name: trimmed, sortOrder: (items.map(\.sortOrder).max() ?? 0) + 1)
        items.append(item)
        saveItems()
        enqueue(DailyIntentionOperation(kind: .create, localId: item.id, name: trimmed, dateKey: Self.todayKey))
    }

    func setCompleted(_ item: DailyIntentionItem, _ completed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].completedAt = completed ? .now : nil
        saveItems()
        if completed, activeIntentionId == item.id {
            clearActiveLink()
        }
        enqueue(DailyIntentionOperation(kind: .setCompleted, localId: item.id, remoteId: items[index].remoteId, completed: completed))
    }

    func remove(_ item: DailyIntentionItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
        if activeIntentionId == item.id {
            clearActiveLink()
        }
        enqueue(DailyIntentionOperation(kind: .delete, localId: item.id, remoteId: item.remoteId))
    }

    /// Remember which intention launched the running timer.
    func linkActive(_ item: DailyIntentionItem) {
        activeIntentionId = item.id
        userDefaults.set(item.id.uuidString, forKey: activeIdKey)
    }

    /// The timer was started from something that isn't an intention.
    func clearActiveLink() {
        activeIntentionId = nil
        userDefaults.removeObject(forKey: activeIdKey)
    }

    /// The running timer was stopped — complete the intention that started it.
    func completeActiveLink() {
        guard let id = activeIntentionId else { return }
        clearActiveLink()
        guard let item = items.first(where: { $0.id == id }), !item.isCompleted else { return }
        setCompleted(item, true)
    }

    /// Load today's canonical list from the backend and merge it into local
    /// state. Skipped while operations are in flight so it never clobbers an
    /// optimistic change that hasn't finished syncing.
    func refresh() async {
        rolloverIfNeeded()
        guard pendingOps.isEmpty else { return }
        let remote: [RemoteIntention]
        do {
            remote = try await DailyIntentionAPI.list(date: Self.todayKey)
        } catch {
            return
        }
        guard pendingOps.isEmpty else { return }
        merge(remote)
    }

    /// Replace local items with the server list, preserving local ids for items
    /// we already know (matched by `remoteId`) so the active link survives.
    private func merge(_ remote: [RemoteIntention]) {
        items = remote.map { intention in
            let existing = items.first { $0.remoteId == intention.id }
            var completedAt: Date?
            if intention.completed {
                completedAt = existing?.completedAt
                    ?? intention.completedAt.flatMap(Self.parseISODate)
                    ?? .now
            }
            return DailyIntentionItem(
                id: existing?.id ?? UUID(),
                remoteId: intention.id,
                name: intention.name,
                completedAt: completedAt,
                sortOrder: intention.sortOrder
            )
        }
        saveItems()
        if let activeIntentionId, !items.contains(where: { $0.id == activeIntentionId }) {
            clearActiveLink()
        }
    }

    /// Intentions are strictly per-day: when the stored day is no longer today,
    /// drop everything (including undelivered ops for the old day's mutations —
    /// an unfinished intention just disappears).
    private func rolloverIfNeeded() {
        let today = Self.todayKey
        guard storedDay != today else { return }
        storedDay = today
        userDefaults.set(today, forKey: dateKey)
        items = []
        saveItems()
        // Keep undelivered creates/completions only if they belong to today
        // (they can't — the day changed), so clear the queue and the link.
        pendingOps = []
        savePending()
        remoteIds = [:]
        saveRemoteIds()
        clearActiveLink()
    }

    // MARK: - Sync queue

    private func enqueue(_ operation: DailyIntentionOperation) {
        pendingOps.append(operation)
        savePending()
        Task { await flush() }
    }

    private func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while let operation = pendingOps.first {
            do {
                try await perform(operation)
                if pendingOps.first?.id == operation.id {
                    pendingOps.removeFirst()
                    savePending()
                }
            } catch {
                guard pendingOps.first?.id == operation.id else { continue }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if pendingOps.first?.id == operation.id {
                    Task { await flush() }
                }
                return
            }
        }

        await refresh()
    }

    private func perform(_ operation: DailyIntentionOperation) async throws {
        switch operation.kind {
        case .create:
            guard let name = operation.name else { return }
            // The operation id doubles as an idempotency key: a retried create
            // returns the existing row instead of duplicating it.
            let intention = try await DailyIntentionAPI.create(
                name: name,
                date: operation.dateKey ?? Self.todayKey,
                clientKey: operation.id.uuidString
            )
            remoteIds[operation.localId] = intention.id
            saveRemoteIds()
            if let index = items.firstIndex(where: { $0.id == operation.localId }) {
                items[index].remoteId = intention.id
                saveItems()
            }
        case .setCompleted:
            guard let remoteId = resolveRemoteId(for: operation) else { return }
            do {
                _ = try await DailyIntentionAPI.setCompleted(id: remoteId, operation.completed ?? true)
            } catch {
                guard Self.canIgnoreMissingError(error) else { throw error }
            }
        case .delete:
            guard let remoteId = resolveRemoteId(for: operation) else { return }
            do {
                try await DailyIntentionAPI.delete(id: remoteId)
            } catch {
                guard Self.canIgnoreMissingError(error) else { throw error }
            }
            remoteIds.removeValue(forKey: operation.localId)
            saveRemoteIds()
        }
    }

    private func resolveRemoteId(for operation: DailyIntentionOperation) -> Int? {
        operation.remoteId
            ?? remoteIds[operation.localId]
            ?? items.first(where: { $0.id == operation.localId })?.remoteId
    }

    /// A patch/delete that 400/404s means the intention is already gone
    /// server-side — treat it as success so the queue drains.
    private static func canIgnoreMissingError(_ error: Error) -> Bool {
        guard let httpError = error as? HTTPClientError,
              case let .httpFailure(statusCode, data) = httpError else {
            return false
        }
        if statusCode == 404 { return true }
        guard statusCode == 400 else { return false }
        let body = (String(data: data, encoding: .utf8) ?? "").lowercased()
        return body.contains("not found")
    }

    // MARK: - Persistence

    private func saveItems() {
        Self.save(items, key: itemsKey, to: userDefaults)
        userDefaults.set(storedDay, forKey: dateKey)
    }

    private func savePending() {
        Self.save(pendingOps, key: pendingKey, to: userDefaults)
    }

    private func saveRemoteIds() {
        let encodable = Dictionary(uniqueKeysWithValues: remoteIds.map { ($0.key.uuidString, $0.value) })
        Self.save(encodable, key: remoteIdsKey, to: userDefaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from userDefaults: UserDefaults) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, to userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }

    // MARK: - Dates

    /// The user's local calendar day, "yyyy-MM-dd" — the backend scopes
    /// intentions by exactly this string.
    static var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

// MARK: - API (/api/mobile/daily-intentions)

/// An intention as returned by the backend.
struct RemoteIntention: Decodable {
    var id: Int
    var name: String
    var date: String
    var sortOrder: Int
    var completed: Bool
    var completedAt: String?
}

enum DailyIntentionAPI {
    private static let baseURL = AppEnvironment.apiURL("mobile/daily-intentions")

    static func list(date: String) async throws -> [RemoteIntention] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "date", value: date)]
        let url = components?.url ?? baseURL
        let response = try await HTTPClient.shared.data(url: url, method: .get)
        return try JSONDecoder().decode(IntentionListEnvelope.self, from: response.data).intentions
    }

    static func create(name: String, date: String, clientKey: String) async throws -> RemoteIntention {
        let body = CreateIntentionRequest(name: name, date: date, clientKey: clientKey)
        let response = try await HTTPClient.shared.data(url: baseURL, method: .post, body: body)
        return try JSONDecoder().decode(IntentionEnvelope.self, from: response.data).intention
    }

    @discardableResult
    static func setCompleted(id: Int, _ completed: Bool) async throws -> RemoteIntention {
        let url = baseURL.appendingPathComponent(String(id))
        let body = PatchIntentionRequest(completed: completed)
        let response = try await HTTPClient.shared.data(url: url, method: .patch, body: body)
        return try JSONDecoder().decode(IntentionEnvelope.self, from: response.data).intention
    }

    static func delete(id: Int) async throws {
        let url = baseURL.appendingPathComponent(String(id))
        _ = try await HTTPClient.shared.data(url: url, method: .delete)
    }
}

private struct IntentionListEnvelope: Decodable {
    var intentions: [RemoteIntention]
}

private struct IntentionEnvelope: Decodable {
    var intention: RemoteIntention
}

private struct CreateIntentionRequest: Encodable {
    var name: String
    var date: String
    var clientKey: String
}

private struct PatchIntentionRequest: Encodable {
    var completed: Bool
}
