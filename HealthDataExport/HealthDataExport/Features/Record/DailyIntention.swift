import Combine
import Foundation
import SwiftUI

/// An intention: something the user plans to do, optionally attached to a
/// goal/project. Only a name — no type, duration or icon. Intentions persist
/// until completed; completed ones show for the rest of the day, then drop
/// off the list (they stay in the database as goal progress).
struct DailyIntentionItem: Codable, Identifiable, Hashable {
    let id: UUID
    /// Backend `daily_intentions.id`. Nil while an optimistically-created
    /// intention is still waiting for its POST to land.
    var remoteId: Int?
    var name: String
    var completedAt: Date?
    var sortOrder: Int
    /// Goal/project this intention advances; nil = 公共 (unattached).
    var goalId: Int?
    var goalName: String?
    var goalKind: String?
    /// Habit-like intention: completing only counts for the day; it comes back
    /// tomorrow. Optional so items persisted before the field existed decode.
    var repeating: Bool?

    var isRepeating: Bool { repeating == true }

    /// "Completed" as the UI understands it: a repeating intention only counts
    /// as completed if it was done *today* — yesterday's completion means it's
    /// open again.
    var isCompleted: Bool {
        guard let completedAt else { return false }
        if isRepeating {
            return completedAt >= Calendar.current.startOfDay(for: .now)
        }
        return true
    }

    init(id: UUID = UUID(), remoteId: Int? = nil, name: String, completedAt: Date? = nil, sortOrder: Int = 0, goalId: Int? = nil, goalName: String? = nil, goalKind: String? = nil, repeating: Bool? = nil) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.goalId = goalId
        self.goalName = goalName
        self.goalKind = goalKind
        self.repeating = repeating
    }
}

/// A queued backend intention operation, persisted so it survives relaunch and
/// is retried until it lands (same optimistic pattern as the shortcut queues).
struct DailyIntentionOperation: Codable, Identifiable {
    enum Kind: String, Codable {
        case create
        case setCompleted
        case rename
        case setRepeating
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
    /// "yyyy-MM-dd" the create was made on, captured at enqueue time.
    var dateKey: String?
    /// Goal the created intention attaches to.
    var goalId: Int?
    var repeating: Bool?

    init(id: UUID = UUID(), kind: Kind, localId: UUID, remoteId: Int? = nil, name: String? = nil, completed: Bool? = nil, dateKey: String? = nil, goalId: Int? = nil, repeating: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.localId = localId
        self.remoteId = remoteId
        self.name = name
        self.completed = completed
        self.dateKey = dateKey
        self.goalId = goalId
        self.repeating = repeating
    }
}

@MainActor
final class DailyIntentionStore: ObservableObject {
    static let shared = DailyIntentionStore()

    @Published private(set) var items: [DailyIntentionItem] = []
    /// Active goals/projects (with progress), loaded for the add sheet.
    @Published private(set) var goals: [RemoteGoal] = []
    /// Intention whose 开始 launched the currently-running timer; completed when
    /// the timer is stopped.
    @Published private(set) var activeIntentionId: UUID?
    /// Called after any visible intention change so paired-device snapshots can
    /// be updated immediately rather than waiting for the view to reopen.
    var onItemsChanged: (() -> Void)?

    private let itemsKey = "dailyIntentions.items"
    private let pendingKey = "dailyIntentions.pendingOps"
    private let remoteIdsKey = "dailyIntentions.remoteIds"
    private let activeIdKey = "dailyIntentions.activeId"
    private let userDefaults: UserDefaults

    private var pendingOps: [DailyIntentionOperation] = []
    private var isFlushing = false
    /// Maps a local item id to its server id once a create lands, so a later
    /// patch/delete can resolve the id even after the item left `items`.
    private var remoteIds: [UUID: Int] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.items = Self.load([DailyIntentionItem].self, key: itemsKey, from: userDefaults) ?? []
        self.pendingOps = Self.load([DailyIntentionOperation].self, key: pendingKey, from: userDefaults) ?? []
        self.remoteIds = Self.load([String: Int].self, key: remoteIdsKey, from: userDefaults)
            .map { Dictionary(uniqueKeysWithValues: $0.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } }) }
            ?? [:]
        self.activeIntentionId = userDefaults.string(forKey: activeIdKey).flatMap(UUID.init(uuidString:))
        // Let queued time-entry starts resolve their intention link at flush
        // time (ShortcutRecord.swift can't reference this store directly — the
        // watch target compiles it without this file).
        ShortcutRecordStore.shared.intentionRemoteIdResolver = { [weak self] localId in
            self?.remoteId(forLocal: localId)
        }
        if !pendingOps.isEmpty {
            Task { await flush() }
        }
    }

    /// The backend id for a local intention id, once its create has landed.
    func remoteId(forLocal id: UUID) -> Int? {
        items.first(where: { $0.id == id })?.remoteId ?? remoteIds[id]
    }

    /// The home list: the running intention pinned first, then the rest of the
    /// incomplete ones (in user order), then the ones completed *today* (in
    /// completion order). Intentions completed on earlier days stay in `items`
    /// as goal progress for the board, but drop off the home list.
    var sortedItems: [DailyIntentionItem] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let open = items.filter { !$0.isCompleted }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let doneToday = items
            .filter { ($0.completedAt ?? .distantPast) >= dayStart }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let active = open.filter { $0.id == activeIntentionId }
        let rest = open.filter { $0.id != activeIntentionId }
        return active + rest + doneToday
    }

    /// Board grouping: intentions under a goal (nil = 公共), incomplete first
    /// (user order) then completed (most recent first).
    func boardItems(goalId: Int?) -> [DailyIntentionItem] {
        let group = items.filter { item in
            if let goalId {
                return item.goalId == goalId
            }
            // 公共 also absorbs intentions whose goal no longer exists.
            return item.goalId == nil || !goals.contains { $0.id == item.goalId }
        }
        let open = group.filter { !$0.isCompleted }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let done = group.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + done
    }

    func add(name: String, goal: RemoteGoal? = nil, repeating: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = DailyIntentionItem(
            name: trimmed,
            sortOrder: (items.map(\.sortOrder).max() ?? 0) + 1,
            goalId: goal?.id,
            goalName: goal?.name,
            goalKind: goal?.kind,
            repeating: repeating ? true : nil
        )
        items.append(item)
        saveItems()
        enqueue(DailyIntentionOperation(kind: .create, localId: item.id, name: trimmed, dateKey: Self.todayKey, goalId: goal?.id, repeating: repeating ? true : nil))
    }

    func rename(_ item: DailyIntentionItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].name = trimmed
        saveItems()
        enqueue(DailyIntentionOperation(kind: .rename, localId: item.id, remoteId: items[index].remoteId, name: trimmed))
    }

    /// Duplicate an intention (completed ones included): same name and goal,
    /// fresh and uncompleted, appended at the end of its group. The copy is
    /// always a plain one-shot intention — the repeating flag doesn't carry
    /// over (a repeating intention comes back by itself; a copy of it is just
    /// an extra one-off).
    func duplicate(_ item: DailyIntentionItem) {
        let copy = DailyIntentionItem(
            name: item.name,
            sortOrder: (items.map(\.sortOrder).max() ?? 0) + 1,
            goalId: item.goalId,
            goalName: item.goalName,
            goalKind: item.goalKind
        )
        items.append(copy)
        saveItems()
        enqueue(DailyIntentionOperation(
            kind: .create,
            localId: copy.id,
            name: copy.name,
            dateKey: Self.todayKey,
            goalId: copy.goalId
        ))
    }

    func setRepeating(_ item: DailyIntentionItem, _ repeating: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].repeating = repeating
        saveItems()
        enqueue(DailyIntentionOperation(kind: .setRepeating, localId: item.id, remoteId: items[index].remoteId, repeating: repeating))
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

    /// Load the canonical list (all incomplete + all completed, for the board)
    /// from the backend and merge it into local state. Skipped while operations
    /// are in flight so it never clobbers an optimistic change that hasn't
    /// synced.
    func refresh() async {
        guard pendingOps.isEmpty else { return }
        let remote: [RemoteIntention]
        do {
            remote = try await DailyIntentionAPI.list(all: true)
        } catch {
            return
        }
        guard pendingOps.isEmpty else { return }
        merge(remote)
    }

    /// Fetch the active goals/projects (with progress) for the add sheet.
    func loadGoals() async {
        do {
            goals = try await GoalAPI.list()
        } catch {
            // Keep whatever we had; the sheet still works with 公共.
        }
    }

    /// Create a goal/project right away (awaited by the add sheet so the new
    /// intention can attach to a real server id).
    func createGoal(name: String, kind: String) async throws -> RemoteGoal {
        let goal = try await GoalAPI.create(name: name, kind: kind)
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        return goal
    }

    /// Rename a goal/project. Optimistic: the group header and every intention
    /// tag update immediately; the PATCH lands in the background.
    func renameGoal(_ goal: RemoteGoal, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != goal.name else { return }
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index].name = trimmed
        }
        var changed = false
        for index in items.indices where items[index].goalId == goal.id {
            items[index].goalName = trimmed
            changed = true
        }
        if changed {
            saveItems()
        }
        Task {
            try? await GoalAPI.rename(id: goal.id, name: trimmed)
            await loadGoals()
        }
    }

    /// Delete a goal/project. Optimistic: the group disappears immediately and
    /// its intentions move to 公共 (mirroring what the backend does — it
    /// detaches them, never deletes them).
    func deleteGoal(_ goal: RemoteGoal) {
        goals.removeAll { $0.id == goal.id }
        var changed = false
        for index in items.indices where items[index].goalId == goal.id {
            items[index].goalId = nil
            items[index].goalName = nil
            items[index].goalKind = nil
            changed = true
        }
        if changed {
            saveItems()
        }
        Task {
            try? await GoalAPI.delete(id: goal.id)
            await loadGoals()
        }
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
                sortOrder: intention.sortOrder,
                goalId: intention.goalId,
                goalName: intention.goalName,
                goalKind: intention.goalKind,
                repeating: intention.repeating
            )
        }
        saveItems()
        if let activeIntentionId, !items.contains(where: { $0.id == activeIntentionId }) {
            clearActiveLink()
        }
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
                clientKey: operation.id.uuidString,
                goalId: operation.goalId
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
                _ = try await DailyIntentionAPI.patch(id: remoteId, completed: operation.completed ?? true)
            } catch {
                guard Self.canIgnoreMissingError(error) else { throw error }
            }
        case .rename:
            guard let remoteId = resolveRemoteId(for: operation), let name = operation.name else { return }
            do {
                _ = try await DailyIntentionAPI.patch(id: remoteId, name: name)
            } catch {
                guard Self.canIgnoreMissingError(error) else { throw error }
            }
        case .setRepeating:
            guard let remoteId = resolveRemoteId(for: operation) else { return }
            do {
                _ = try await DailyIntentionAPI.patch(id: remoteId, repeating: operation.repeating ?? false)
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
        onItemsChanged?()
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

    /// The user's local calendar day, "yyyy-MM-dd" — sent to the backend as
    /// "include intentions completed on/after this day".
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
    var goalId: Int?
    var goalName: String?
    var goalKind: String?
    var repeating: Bool?
}

/// A goal/project as returned by `/api/mobile/goals`, with intention progress.
struct RemoteGoal: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String
    /// "goal" or "project".
    var kind: String
    var status: String
    var sortOrder: Int
    var totalIntentions: Int
    var completedIntentions: Int
    var trackedSeconds: Int?

    var isProject: Bool { kind == "project" }
}

enum DailyIntentionAPI {
    private static let baseURL = AppEnvironment.apiURL("mobile/daily-intentions")

    /// `all` fetches every completed intention (for the board); otherwise only
    /// the ones completed today come back alongside the incomplete list.
    static func list(all: Bool = false) async throws -> [RemoteIntention] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = all
            ? [URLQueryItem(name: "all", value: "true")]
            : [URLQueryItem(name: "date", value: DailyIntentionStore.todayKey)]
        let url = components?.url ?? baseURL
        let response = try await HTTPClient.shared.data(url: url, method: .get)
        return try JSONDecoder().decode(IntentionListEnvelope.self, from: response.data).intentions
    }

    static func create(name: String, date: String, clientKey: String, goalId: Int? = nil, repeating: Bool? = nil) async throws -> RemoteIntention {
        let body = CreateIntentionRequest(name: name, date: date, clientKey: clientKey, goalId: goalId, repeating: repeating)
        let response = try await HTTPClient.shared.data(url: baseURL, method: .post, body: body)
        return try JSONDecoder().decode(IntentionEnvelope.self, from: response.data).intention
    }

    /// General PATCH — only the fields passed are touched.
    @discardableResult
    static func patch(id: Int, name: String? = nil, completed: Bool? = nil, repeating: Bool? = nil) async throws -> RemoteIntention {
        let url = baseURL.appendingPathComponent(String(id))
        let body = PatchIntentionRequest(name: name, completed: completed, repeating: repeating)
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
    var goalId: Int?
    var repeating: Bool?
}

private struct PatchIntentionRequest: Encodable {
    var name: String?
    var completed: Bool?
    var repeating: Bool?
}

// MARK: - Goals API (/api/mobile/goals)

enum GoalAPI {
    private static let baseURL = AppEnvironment.apiURL("mobile/goals")

    static func list() async throws -> [RemoteGoal] {
        let response = try await HTTPClient.shared.data(url: baseURL, method: .get)
        return try JSONDecoder().decode(GoalListEnvelope.self, from: response.data).goals
    }

    static func create(name: String, kind: String) async throws -> RemoteGoal {
        let body = CreateGoalRequest(name: name, kind: kind)
        let response = try await HTTPClient.shared.data(url: baseURL, method: .post, body: body)
        return try JSONDecoder().decode(GoalEnvelope.self, from: response.data).goal
    }

    static func rename(id: Int, name: String) async throws {
        let url = baseURL.appendingPathComponent(String(id))
        _ = try await HTTPClient.shared.data(url: url, method: .patch, body: PatchGoalRequest(name: name))
    }

    static func delete(id: Int) async throws {
        let url = baseURL.appendingPathComponent(String(id))
        _ = try await HTTPClient.shared.data(url: url, method: .delete)
    }
}

private struct PatchGoalRequest: Encodable {
    var name: String
}

private struct GoalListEnvelope: Decodable {
    var goals: [RemoteGoal]
}

private struct GoalEnvelope: Decodable {
    var goal: RemoteGoal
}

private struct CreateGoalRequest: Encodable {
    var name: String
    var kind: String
}
