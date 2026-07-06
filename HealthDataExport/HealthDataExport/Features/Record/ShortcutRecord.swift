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
    /// Backend `time_shortcuts.id`. Nil while an optimistically-created shortcut
    /// is still waiting for its POST to land (mirrors the Fitness template flow).
    var remoteId: Int?
    var name: String
    var symbolName: String
    var colorHex: String
    var categoryId: String?
    var subtypeId: String?
    /// Human-readable big-category label (e.g. "生活"), shown in the list subtitle.
    var categoryName: String?
    /// Default/estimated duration in minutes, shown as "预计 N 分钟" when present.
    var defaultDurationMinutes: Int?

    init(id: UUID = UUID(), remoteId: Int? = nil, name: String, symbolName: String, colorHex: String, categoryId: String? = nil, subtypeId: String? = nil, categoryName: String? = nil, defaultDurationMinutes: Int? = nil) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.categoryId = categoryId
        self.subtypeId = subtypeId
        self.categoryName = categoryName
        self.defaultDurationMinutes = defaultDurationMinutes
    }

    /// Build a task from a backend shortcut. The backend doesn't persist a
    /// per-shortcut SF Symbol, so the icon is derived from the type's icon
    /// (falling back to the name) and the color falls back through
    /// type → category → accent.
    init(remote: RemoteShortcut) {
        self.init(
            id: UUID(),
            remoteId: remote.id,
            name: remote.name,
            symbolName: ShortcutRecordStore.resolvedSymbol(typeIcon: remote.typeIcon, name: remote.name),
            colorHex: RemoteShortcut.normalizeHex(remote.typeColor ?? remote.categoryColor) ?? Self.defaultColorHex,
            categoryId: remote.categoryId.map(String.init),
            subtypeId: remote.typeId.map(String.init),
            categoryName: remote.categoryName,
            defaultDurationMinutes: remote.defaultDurationMinutes
        )
    }

    static let defaultColorHex = "FF7847"

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

/// A queued backend time-entry operation, persisted so it survives relaunch and
/// can be retried until it lands (mirrors the Fitness session operation queue).
struct ShortcutSyncOperation: Codable, Identifiable {
    enum Kind: String, Codable {
        case start
        case end
    }

    let id: UUID
    let kind: Kind
    let taskName: String
    let typeId: String?
    let note: String

    init(id: UUID = UUID(), kind: Kind, taskName: String = "", typeId: String? = nil, note: String = "") {
        self.id = id
        self.kind = kind
        self.taskName = taskName
        self.typeId = typeId
        self.note = note
    }
}

/// A queued backend shortcut CRUD operation (create / update / delete), persisted
/// so it survives relaunch and is retried until it lands. The UI mutates local
/// state immediately and pushes here — nothing waits on the network. Operations
/// reference the task by its local `UUID`; the server id is resolved at flush
/// time (a create earlier in the FIFO queue populates it first).
struct ShortcutCrudOperation: Codable, Identifiable {
    enum Kind: String, Codable {
        case create
        case update
        case delete
    }

    let id: UUID
    let kind: Kind
    /// Local `ShortcutTask.id` this operation targets.
    let localId: UUID
    /// Known backend id at enqueue time (set for edits/deletes of synced tasks).
    var remoteId: Int?
    // Mutation payload — only the fields that should change are non-nil.
    var name: String?
    var taskName: String?
    var typeId: Int?
    var sortOrder: Int?
    var note: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        localId: UUID,
        remoteId: Int? = nil,
        name: String? = nil,
        taskName: String? = nil,
        typeId: Int? = nil,
        sortOrder: Int? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.localId = localId
        self.remoteId = remoteId
        self.name = name
        self.taskName = taskName
        self.typeId = typeId
        self.sortOrder = sortOrder
        self.note = note
    }
}

@MainActor
final class ShortcutRecordStore: ObservableObject {
    static let shared = ShortcutRecordStore()

    @Published var tasks: [ShortcutTask]
    @Published var activeSession: ActiveShortcutSession?
    @Published var events: [ShortcutEvent]
    /// Non-empty while a queued start/end operation is failing and being retried.
    @Published var syncStatusMessage: String = ""

    private let tasksKey = "shortcutRecord.tasks"
    private let activeKey = "shortcutRecord.activeSession"
    private let eventsKey = "shortcutRecord.events"
    private let pendingSyncKey = "shortcutRecord.pendingSync"
    private let pendingCrudKey = "shortcutRecord.pendingCrud"
    private let remoteIdsKey = "shortcutRecord.remoteIds"
    private let userDefaults: UserDefaults

    /// Backend start/end operations queued for delivery. Mirrors the Fitness
    /// session queue: the UI mutates local state immediately and pushes here,
    /// so nothing waits on the network.
    private var pendingSync: [ShortcutSyncOperation]
    private var isFlushingSync = false

    /// Backend shortcut create/update/delete operations queued for delivery,
    /// same optimistic pattern as `pendingSync`.
    private var pendingCrud: [ShortcutCrudOperation]
    private var isFlushingCrud = false
    /// Maps a local task id to its server id once a create lands, so a later
    /// update/delete for the same task can resolve the id even after the task
    /// was removed from `tasks`.
    private var remoteIds: [UUID: Int]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.tasks = Self.load([ShortcutTask].self, key: tasksKey, from: userDefaults) ?? Self.defaultTasks
        self.activeSession = Self.load(ActiveShortcutSession.self, key: activeKey, from: userDefaults)
        self.events = Self.load([ShortcutEvent].self, key: eventsKey, from: userDefaults) ?? Self.defaultEvents
        self.pendingSync = Self.load([ShortcutSyncOperation].self, key: pendingSyncKey, from: userDefaults) ?? []
        self.pendingCrud = Self.load([ShortcutCrudOperation].self, key: pendingCrudKey, from: userDefaults) ?? []
        self.remoteIds = Self.load([String: Int].self, key: remoteIdsKey, from: userDefaults)
            .map { Dictionary(uniqueKeysWithValues: $0.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } }) }
            ?? [:]
        if !pendingSync.isEmpty {
            Task { await flushSync() }
        }
        if !pendingCrud.isEmpty {
            Task { await flushCrud() }
        }
    }

    func addTask(name: String, template: ShortcutTask, categoryId: String?, subtypeId: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let task = ShortcutTask(
            name: trimmedName,
            symbolName: template.symbolName,
            colorHex: template.colorHex,
            categoryId: categoryId,
            subtypeId: subtypeId
        )
        tasks.append(task)
        saveTasks()
        enqueueCrud(ShortcutCrudOperation(
            kind: .create,
            localId: task.id,
            name: task.name,
            taskName: task.name,
            typeId: subtypeId.flatMap { Int($0) },
            sortOrder: tasks.count - 1
        ))
    }

    /// Apply an edit to an existing shortcut: mutate local state immediately and
    /// queue a PATCH.
    func updateTask(_ task: ShortcutTask, name: String, template: ShortcutTask, categoryId: String?, subtypeId: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = tasks[index]
        updated.name = trimmedName
        updated.symbolName = template.symbolName
        updated.colorHex = template.colorHex
        updated.categoryId = categoryId
        updated.subtypeId = subtypeId
        tasks[index] = updated
        if activeSession?.task.id == task.id {
            activeSession?.task = updated
            saveActiveSession()
        }
        saveTasks()
        enqueueCrud(ShortcutCrudOperation(
            kind: .update,
            localId: updated.id,
            remoteId: updated.remoteId,
            name: trimmedName,
            taskName: trimmedName,
            typeId: subtypeId.flatMap { Int($0) }
        ))
    }

    func removeTask(_ task: ShortcutTask) {
        tasks.removeAll { $0.id == task.id }
        if activeSession?.task.id == task.id {
            activeSession = nil
            saveActiveSession()
            enqueueSync(ShortcutSyncOperation(kind: .end))
        }
        saveTasks()
        enqueueCrud(ShortcutCrudOperation(kind: .delete, localId: task.id, remoteId: task.remoteId))
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
        saveTasks()
        // Persist the new order: PATCH each task's sortOrder to its index.
        for (index, task) in tasks.enumerated() {
            enqueueCrud(ShortcutCrudOperation(
                kind: .update,
                localId: task.id,
                remoteId: task.remoteId,
                sortOrder: index
            ))
        }
    }

    /// Load the canonical shortcut list from the backend and merge it into local
    /// state. Skipped while CRUD operations are in flight so it never clobbers an
    /// optimistic change that hasn't finished syncing (same guard as
    /// `syncRunningSession`).
    func refreshTasks() async {
        guard pendingCrud.isEmpty else { return }
        let remote: [RemoteShortcut]
        do {
            remote = try await ShortcutAPI.listShortcuts()
        } catch {
            return
        }
        // A create may have been queued while the request was in flight.
        guard pendingCrud.isEmpty else { return }
        merge(remote)
    }

    /// Replace local tasks with the server list, preserving the user's chosen
    /// icon/color for shortcuts we already know (matched by `remoteId`).
    private func merge(_ remote: [RemoteShortcut]) {
        tasks = remote.map { shortcut in
            if let existing = tasks.first(where: { $0.remoteId == shortcut.id }) {
                var task = existing
                task.name = shortcut.name
                task.categoryId = shortcut.categoryId.map(String.init)
                task.subtypeId = shortcut.typeId.map(String.init)
                return task
            }
            return ShortcutTask(remote: shortcut)
        }
        saveTasks()
    }

    func start(_ task: ShortcutTask) {
        let wasRunning = activeSession != nil
        activeSession = ActiveShortcutSession(task: task, startedAt: .now)
        events.insert(ShortcutEvent(task: task, kind: .started, note: "开始了"), at: 0)
        saveActiveSession()
        saveEvents()
        let startOp = ShortcutSyncOperation(kind: .start, taskName: task.name, typeId: task.subtypeId)
        // Preserve an `end` that was queued (e.g. by a 结束 tapped moments ago) but
        // hasn't been delivered yet. Blindly replacing the queue would strand the
        // previous entry as RUNNING on the backend, so the fresh start would 409
        // with "a time entry is already running". Carrying the end over (with its
        // note) keeps the server consistent.
        if let pendingEnd = pendingSync.first(where: { $0.kind == .end }) {
            replaceSyncQueue([pendingEnd, startOp])
        } else if wasRunning {
            replaceSyncQueue([ShortcutSyncOperation(kind: .end), startOp])
        } else {
            replaceSyncQueue([startOp])
        }
    }

    func stop(note: String) {
        guard let activeSession else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        events.insert(ShortcutEvent(task: activeSession.task, kind: .stopped, note: trimmedNote.isEmpty ? "结束了" : trimmedNote), at: 0)
        self.activeSession = nil
        saveActiveSession()
        saveEvents()
        replaceSyncQueue([ShortcutSyncOperation(kind: .end, note: trimmedNote)])
    }

    /// Apply an active-entry change that originated on the *watch* (relayed via
    /// WatchConnectivity). Updates local state only — the watch already wrote the
    /// backend — and persists silently so it isn't echoed back to the watch.
    func applyRemoteActive(_ activity: SharedActiveActivity?) {
        let incoming = activity.map { ($0.name, $0.startedAt) }
        let current = activeSession.map { ($0.task.name, $0.startedAt) }
        if incoming?.0 == current?.0, incoming?.1 == current?.1 { return }

        if let activity {
            let task = tasks.first { $0.name == activity.name }
                ?? ShortcutTask(name: activity.name, symbolName: activity.symbolName, colorHex: activity.colorHex)
            activeSession = ActiveShortcutSession(task: task, startedAt: activity.startedAt)
        } else {
            activeSession = nil
        }
        Self.save(activeSession, key: activeKey, to: userDefaults)
        SharedActivityStore.writeSilently(activeSession.map {
            SharedActiveActivity(
                name: $0.task.name,
                startedAt: $0.startedAt,
                colorHex: $0.task.colorHex,
                symbolName: $0.task.symbolName
            )
        })
    }

    func sharedActiveActivity() -> SharedActiveActivity? {
        activeSession.map {
            SharedActiveActivity(
                name: $0.task.name,
                startedAt: $0.startedAt,
                colorHex: $0.task.colorHex,
                symbolName: $0.task.symbolName
            )
        }
    }

    func syncRunningSession(_ runningEntry: RunningShortcutEntry?) {
        // Don't let stale server state clobber optimistic changes that haven't
        // finished syncing yet.
        guard pendingSync.isEmpty else { return }
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

    // MARK: - Backend sync queue

    private func enqueueSync(_ operation: ShortcutSyncOperation) {
        pendingSync.append(operation)
        savePendingSync()
        Task { await flushSync() }
    }

    private func replaceSyncQueue(_ operations: [ShortcutSyncOperation]) {
        pendingSync = operations
        savePendingSync()
        syncStatusMessage = ""
        Task { await flushSync() }
    }

    private func flushSync() async {
        guard !isFlushingSync else { return }
        isFlushingSync = true
        defer { isFlushingSync = false }

        while let operation = pendingSync.first {
            do {
                switch operation.kind {
                case .start:
                    do {
                        try await ShortcutAPI.start(taskName: operation.taskName, typeId: operation.typeId)
                    } catch {
                        // A 409 "already running" means the backend still has a
                        // running entry our local state lost track of (e.g. a
                        // previous end never landed). Retrying the same start is
                        // futile — it will 409 forever and, because pendingSync
                        // never empties, syncRunningSession can never self-heal.
                        // Reconcile instead: if it's already our task, we're done;
                        // otherwise end it first, then start ours.
                        guard Self.isAlreadyRunningError(error) else { throw error }
                        let running = try await ShortcutAPI.running()
                        if running?.taskName != operation.taskName {
                            if running != nil {
                                try? await ShortcutAPI.end(note: "")
                            }
                            try await ShortcutAPI.start(taskName: operation.taskName, typeId: operation.typeId)
                        }
                    }
                case .end:
                    do {
                        try await ShortcutAPI.end(note: operation.note)
                    } catch {
                        guard Self.canIgnoreEndError(error) else { throw error }
                    }
                }
                if pendingSync.first?.id == operation.id {
                    pendingSync.removeFirst()
                    savePendingSync()
                    syncStatusMessage = ""
                }
            } catch {
                guard pendingSync.first?.id == operation.id else {
                    continue
                }
                syncStatusMessage = "同步失败：\(Self.readableMessage(for: error))"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if pendingSync.first?.id == operation.id {
                    Task { await flushSync() }
                }
                return
            }
        }
    }

    private func savePendingSync() {
        Self.save(pendingSync, key: pendingSyncKey, to: userDefaults)
    }

    // MARK: - Backend CRUD queue

    private func enqueueCrud(_ operation: ShortcutCrudOperation) {
        pendingCrud.append(operation)
        savePendingCrud()
        Task { await flushCrud() }
    }

    private func flushCrud() async {
        guard !isFlushingCrud else { return }
        isFlushingCrud = true
        defer { isFlushingCrud = false }

        while let operation = pendingCrud.first {
            do {
                try await perform(operation)
                if pendingCrud.first?.id == operation.id {
                    pendingCrud.removeFirst()
                    savePendingCrud()
                    syncStatusMessage = ""
                }
            } catch {
                guard pendingCrud.first?.id == operation.id else { continue }
                syncStatusMessage = "同步失败：\(Self.readableMessage(for: error))"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if pendingCrud.first?.id == operation.id {
                    Task { await flushCrud() }
                }
                return
            }
        }

        // Once the queue drains, pull the canonical list so server-assigned ids,
        // ordering and type metadata reconcile.
        await refreshTasks()
    }

    private func perform(_ operation: ShortcutCrudOperation) async throws {
        switch operation.kind {
        case .create:
            let shortcut: RemoteShortcut
            do {
                shortcut = try await ShortcutAPI.createShortcut(ShortcutMutationRequest(
                    name: operation.name,
                    taskName: operation.taskName,
                    typeId: operation.typeId,
                    sortOrder: operation.sortOrder,
                    note: operation.note
                ))
            } catch {
                // The name already exists server-side (e.g. created on another
                // device) — nothing to do; let the queue drain and reconcile ids
                // via the refresh that follows.
                guard Self.canIgnoreExistsError(error) else { throw error }
                return
            }
            remoteIds[operation.localId] = shortcut.id
            saveRemoteIds()
            if let index = tasks.firstIndex(where: { $0.id == operation.localId }) {
                tasks[index].remoteId = shortcut.id
                saveTasks()
            }
        case .update:
            guard let remoteId = resolveRemoteId(for: operation) else { return }
            _ = try await ShortcutAPI.updateShortcut(id: remoteId, ShortcutMutationRequest(
                name: operation.name,
                taskName: operation.taskName,
                typeId: operation.typeId,
                sortOrder: operation.sortOrder,
                note: operation.note
            ))
        case .delete:
            guard let remoteId = resolveRemoteId(for: operation) else { return }
            do {
                try await ShortcutAPI.deleteShortcut(id: remoteId)
            } catch {
                guard Self.canIgnoreMissingError(error) else { throw error }
            }
            remoteIds.removeValue(forKey: operation.localId)
            saveRemoteIds()
        }
    }

    /// Resolve the server id for an update/delete: the id captured at enqueue
    /// time, else the one recorded when the task's create landed.
    private func resolveRemoteId(for operation: ShortcutCrudOperation) -> Int? {
        operation.remoteId
            ?? remoteIds[operation.localId]
            ?? tasks.first(where: { $0.id == operation.localId })?.remoteId
    }

    private func savePendingCrud() {
        Self.save(pendingCrud, key: pendingCrudKey, to: userDefaults)
    }

    private func saveRemoteIds() {
        let encodable = Dictionary(uniqueKeysWithValues: remoteIds.map { ($0.key.uuidString, $0.value) })
        Self.save(encodable, key: remoteIdsKey, to: userDefaults)
    }

    private static func readableMessage(for error: Error) -> String {
        if let apiError = error as? ShortcutAPIError {
            return apiError.message
        }
        if let httpError = error as? HTTPClientError,
           case let .httpFailure(statusCode, data) = httpError {
            if let apiError = try? JSONDecoder().decode(TimeEntryErrorResponse.self, from: data) {
                return "\(apiError.error) (\(statusCode))"
            }
            return "HTTP \(statusCode)"
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return error.localizedDescription
    }

    private static func canIgnoreEndError(_ error: Error) -> Bool {
        if let apiError = error as? ShortcutAPIError {
            let normalized = apiError.message.lowercased()
            return [404, 409].contains(apiError.statusCode)
                || normalized.contains("no running")
                || normalized.contains("not running")
                || normalized.contains("没有进行")
                || normalized.contains("没有正在")
        }
        if let httpError = error as? HTTPClientError,
           case let .httpFailure(statusCode, data) = httpError {
            guard [404, 409].contains(statusCode) else { return false }
            let body = (String(data: data, encoding: .utf8) ?? "").lowercased()
            return body.contains("no running")
                || body.contains("not running")
                || body.contains("没有进行")
                || body.contains("没有正在")
                || body.isEmpty
        }
        return false
    }

    /// A start rejected because the backend already has a running entry (409
    /// CONFLICT / "a time entry is already running"). Signals that we should
    /// reconcile rather than blindly retry the identical, permanently-failing
    /// request.
    private static func isAlreadyRunningError(_ error: Error) -> Bool {
        if let apiError = error as? ShortcutAPIError {
            let normalized = apiError.message.lowercased()
            return apiError.statusCode == 409
                || normalized.contains("already running")
                || normalized.contains("正在进行")
                || normalized.contains("已有")
        }
        if let httpError = error as? HTTPClientError,
           case let .httpFailure(statusCode, data) = httpError {
            if statusCode == 409 { return true }
            let body = (String(data: data, encoding: .utf8) ?? "").lowercased()
            return body.contains("already running")
        }
        return false
    }

    /// A create whose name already exists server-side — treat it as success so
    /// the queue drains; the follow-up refresh reconciles the real id.
    private static func canIgnoreExistsError(_ error: Error) -> Bool {
        if let apiError = error as? ShortcutAPIError {
            let normalized = apiError.message.lowercased()
            return apiError.statusCode == 409
                || normalized.contains("already exists")
                || normalized.contains("已存在")
        }
        if let httpError = error as? HTTPClientError,
           case let .httpFailure(statusCode, data) = httpError {
            if statusCode == 409 { return true }
            let body = (String(data: data, encoding: .utf8) ?? "").lowercased()
            return body.contains("already exists") || body.contains("已存在")
        }
        return false
    }

    /// A delete that 404/409s means the shortcut is already gone server-side —
    /// treat it as success so the queue drains.
    private static func canIgnoreMissingError(_ error: Error) -> Bool {
        if let apiError = error as? ShortcutAPIError {
            return [404, 409].contains(apiError.statusCode)
        }
        if let httpError = error as? HTTPClientError,
           case let .httpFailure(statusCode, _) = httpError {
            return [404, 409].contains(statusCode)
        }
        return false
    }

    private func saveTasks() {
        Self.save(tasks, key: tasksKey, to: userDefaults)
    }

    private func saveActiveSession() {
        Self.save(activeSession, key: activeKey, to: userDefaults)
        // Mirror the running activity into the App Group so the watch-face
        // complication can show it (and clear it when nothing is running).
        SharedActivityStore.write(sharedActiveActivity())
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

    /// Resolve the SF Symbol a shortcut should show, preferring the small
    /// category's icon, then the big category's, then a guess from the name.
    /// This is what powers "pick 大类/小类 → icon appears automatically": the
    /// backend already assigns a meaningful (lucide) icon per type, so we just
    /// translate it to the matching SF Symbol.
    nonisolated static func resolvedSymbol(typeIcon: String?, categoryIcon: String? = nil, name: String = "") -> String {
        if let symbol = sfSymbol(forLucide: typeIcon) { return symbol }
        if let symbol = sfSymbol(forLucide: categoryIcon) { return symbol }
        return symbolName(for: name)
    }

    /// Translate a backend lucide glyph id (e.g. "dumbbell") into the closest
    /// SF Symbol. Returns nil when the name is blank or unmapped so callers can
    /// fall back. Covers the icons seeded by the life-os category bootstrap.
    nonisolated static func sfSymbol(forLucide lucide: String?) -> String? {
        guard let key = lucide?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !key.isEmpty else {
            return nil
        }
        let map: [String: String] = [
            // Big categories
            "briefcase": "briefcase.fill",
            "book-open": "book.fill",
            "heart-pulse": "heart.fill",
            "home": "house.fill",
            "sparkles": "sparkles",
            "gamepad-2": "gamecontroller.fill",
            "moon": "moon.fill",
            "target": "target",
            // Small categories
            "brain": "brain.head.profile",
            "messages": "bubble.left.and.bubble.right.fill",
            "list-checks": "checklist",
            "list-todo": "checklist",
            "wrench": "wrench.adjustable.fill",
            "kanban-square": "square.grid.2x2.fill",
            "monitor": "desktopcomputer",
            "languages": "globe",
            "book": "book.closed.fill",
            "graduation-cap": "graduationcap.fill",
            "pen-tool": "pencil.tip.crop.circle",
            "dumbbell": "dumbbell.fill",
            "activity": "figure.run",
            "footprints": "figure.walk",
            "leaf": "leaf.fill",
            "stethoscope": "stethoscope",
            "baby": "figure.child",
            "car-front": "car.fill",
            "house": "house.fill",
            "heart-handshake": "hands.sparkles.fill",
            "users": "person.2.fill",
            "utensils": "fork.knife",
            "sofa": "sofa.fill",
            "shopping-cart": "cart.fill",
            "train-front": "tram.fill",
            "clipboard-list": "list.clipboard.fill",
            "smartphone": "iphone",
            "clapperboard": "film.fill",
            "party-popper": "party.popper.fill",
            "palette": "paintpalette.fill",
            "bed": "bed.double.fill",
            "lamp": "lamp.desk.fill",
            "alarm-clock-off": "alarm.fill",
            "files": "folder.fill",
            "folder": "folder.fill",
            "lightbulb": "lightbulb.fill",
            "clock": "clock.fill",
            "circle": "circle.fill",
        ]
        return map[key]
    }

    /// Derive an SF Symbol from a shortcut's name. The backend stores a per-type
    /// icon that isn't guaranteed to be an SF Symbol, so shortcuts fetched from
    /// the server map their name to a symbol the same way the watch does.
    nonisolated static func symbolName(for label: String) -> String {
        let mappings: [(String, String)] = [
            ("编程", "chevron.left.forwardslash.chevron.right"),
            ("代码", "chevron.left.forwardslash.chevron.right"),
            ("会议", "briefcase.fill"),
            ("开会", "briefcase.fill"),
            ("写作", "pencil"),
            ("日记", "pencil"),
            ("设计", "paintbrush.fill"),
            ("阅读", "book.fill"),
            ("课程", "graduationcap.fill"),
            ("笔记", "note.text"),
            ("练习", "checklist"),
            ("吃饭", "fork.knife"),
            ("购物", "cart.fill"),
            ("通勤", "car.fill"),
            ("家务", "house.fill"),
            ("健身", "dumbbell.fill"),
            ("跑步", "figure.run"),
            ("瑜伽", "figure.mind.and.body"),
            ("睡眠", "moon.stars.fill"),
            ("冥想", "figure.mind.and.body"),
            ("休息", "cup.and.saucer.fill"),
            ("游戏", "gamecontroller.fill"),
            ("音乐", "music.note"),
            ("视频", "video.fill"),
            ("社交", "heart.fill"),
            ("健康", "heart")
        ]
        return mappings.first { label.contains($0.0) }?.1 ?? "bolt.fill"
    }

    nonisolated static let defaultTasks: [ShortcutTask] = [
        ShortcutTask(name: "写代码", symbolName: "chevron.left.forwardslash.chevron.right", colorHex: "FF7847"),
        ShortcutTask(name: "阅读", symbolName: "book", colorHex: "FF7847"),
        ShortcutTask(name: "健身", symbolName: "dumbbell", colorHex: "FF7847"),
        ShortcutTask(name: "开会", symbolName: "briefcase", colorHex: "FF7847"),
        ShortcutTask(name: "吃饭", symbolName: "fork.knife", colorHex: "FF7847"),
        ShortcutTask(name: "休息", symbolName: "cup.and.saucer", colorHex: "FF7847")
    ]

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
    static let runningURL = AppEnvironment.apiURL("mobile/time-entries/running")
    static let startURL = AppEnvironment.apiURL("mobile/time-entries/start")
    static let endURL = AppEnvironment.apiURL("mobile/time-entries/end")
    static let categoriesURL = AppEnvironment.apiURL("time-categories")
    static let shortcutsURL = AppEnvironment.apiURL("mobile/time-shortcuts")

    // MARK: - Shortcut CRUD (/api/mobile/time-shortcuts)

    static func listShortcuts() async throws -> [RemoteShortcut] {
        let response = try await request(url: shortcutsURL, method: .get, body: Optional<String>.none)
        return try JSONDecoder().decode(ShortcutListEnvelope.self, from: response.data).shortcuts
    }

    static func createShortcut(_ body: ShortcutMutationRequest) async throws -> RemoteShortcut {
        let response = try await request(url: shortcutsURL, method: .post, body: body)
        return try JSONDecoder().decode(ShortcutEnvelope.self, from: response.data).shortcut
    }

    static func updateShortcut(id: Int, _ body: ShortcutMutationRequest) async throws -> RemoteShortcut {
        let url = shortcutsURL.appendingPathComponent(String(id))
        let response = try await request(url: url, method: .patch, body: body)
        return try JSONDecoder().decode(ShortcutEnvelope.self, from: response.data).shortcut
    }

    static func deleteShortcut(id: Int) async throws {
        let url = shortcutsURL.appendingPathComponent(String(id))
        _ = try await request(url: url, method: .delete, body: Optional<String>.none)
    }

    /// Shared request wrapper that maps HTTP failures to `ShortcutAPIError`.
    @discardableResult
    private static func request<Body: Encodable>(url: URL, method: HTTPMethod, body: Body?) async throws -> HTTPClientResponse {
        do {
            return try await HTTPClient.shared.data(url: url, method: method, body: body)
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                throw apiError(from: data, statusCode: statusCode)
            }
            throw error
        }
    }

    static func running() async throws -> RunningShortcutEntry? {
        let response: HTTPClientResponse
        do {
            response = try await HTTPClient.shared.data(url: runningURL, method: .get)
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                if statusCode == 204 { return nil }
                throw apiError(from: data, statusCode: statusCode)
            }
            throw error
        }

        if response.statusCode == 204 { return nil }
        return try JSONDecoder.timeEntryDecoder.decode(TimeEntryResponse.self, from: response.data).runningEntry
    }

    static func categories() async throws -> [ShortcutCategory] {
        let response = try await HTTPClient.shared.data(url: categoriesURL, method: .get)
        let decoded = try JSONDecoder().decode(ShortcutCategoriesResponse.self, from: response.data)
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
        do {
            try await post(url: startURL, body: requestBody)
        } catch {
            guard typeId != nil, shouldRetryStartWithoutType(error) else { throw error }
            let fallbackBody = StartTimeEntryRequest(
                taskName: taskName,
                typeId: nil,
                startedAt: Date().apiISOString,
                source: "mobile",
                note: nil
            )
            try await post(url: startURL, body: fallbackBody)
        }
    }

    static func end(note: String) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestBody = EndTimeEntryRequest(note: trimmedNote.isEmpty ? nil : trimmedNote)
        try await post(url: endURL, body: requestBody)
    }

    private static func post<T: Encodable>(url: URL, body: T) async throws {
        do {
            _ = try await HTTPClient.shared.data(url: url, method: .post, body: body)
        } catch let error as HTTPClientError {
            if case let .httpFailure(statusCode, data) = error {
                throw apiError(from: data, statusCode: statusCode)
            }
            throw error
        }
    }

    private static func apiError(from data: Data, statusCode: Int) -> Error {
        if let errorResponse = try? JSONDecoder().decode(TimeEntryErrorResponse.self, from: data) {
            return ShortcutAPIError(statusCode: statusCode, message: errorResponse.error)
        }
        return URLError(.badServerResponse)
    }

    private static func shouldRetryStartWithoutType(_ error: Error) -> Bool {
        guard let apiError = error as? ShortcutAPIError else { return false }
        let message = apiError.message.lowercased()
        return apiError.statusCode == 400 && (
            message.contains("event type not found") ||
            message.contains("type not found") ||
            message.contains("类型不存在")
        )
    }
}

/// A shortcut as returned by `/api/mobile/time-shortcuts`.
struct RemoteShortcut: Decodable {
    var id: Int
    var name: String
    var taskName: String?
    var typeId: Int?
    var categoryId: Int?
    var categoryName: String?
    var typeName: String?
    var categoryColor: String?
    var typeColor: String?
    var typeIcon: String?
    var sortOrder: Int?
    var note: String?
    var defaultDurationMinutes: Int?
    var running: Bool?

    /// Strip a leading `#` (and reject blanks) so the value works with `Color(hex:)`.
    static func normalizeHex(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.replacingOccurrences(of: "#", with: "")
    }
}

/// Body for shortcut create (POST) and update (PATCH). Optional fields are
/// omitted from the JSON when nil, so a PATCH only touches what changed.
struct ShortcutMutationRequest: Encodable {
    var name: String?
    var taskName: String?
    var typeId: Int?
    var sortOrder: Int?
    var note: String?
    var defaultDurationMinutes: Int?
}

private struct ShortcutListEnvelope: Decodable {
    var shortcuts: [RemoteShortcut]
}

private struct ShortcutEnvelope: Decodable {
    var shortcut: RemoteShortcut
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
        if let array = try? [RemoteCategoryResponse](from: decoder) {
            categories = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent([RemoteCategoryResponse].self, forKey: .categories) {
            categories = value
        } else if let value = try container.decodeIfPresent([RemoteCategoryResponse].self, forKey: .data) {
            categories = value
        } else if let value = try container.decodeIfPresent([RemoteCategoryResponse].self, forKey: .items) {
            categories = value
        } else {
            categories = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case categories, data, items
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
