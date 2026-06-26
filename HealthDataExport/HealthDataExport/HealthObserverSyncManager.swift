import Combine
import Foundation
import HealthKit
import UIKit

struct HealthObserverLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let level: String
    let message: String

    init(id: UUID = UUID(), createdAt: Date = .now, level: String, message: String) {
        self.id = id
        self.createdAt = createdAt
        self.level = level
        self.message = message
    }
}

@MainActor
final class HealthObserverSyncManager: ObservableObject {
    static let shared = HealthObserverSyncManager()

    @Published var isEnabled: Bool
    @Published private(set) var statusText = "未启动自动同步"
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var logs: [HealthObserverLogEntry]

    private let healthStore = HKHealthStore()
    private let exporter = HealthKitExporter()
    private var observedTypes: Set<HKSampleType> = []
    private var observerQueries: [HKObserverQuery] = []
    private var isSyncing = false
    private var hasStarted = false
    private var activeConfigurationSignature: String?
    private var pendingRetryReason: String?
    private var pendingRetryMetricIDs: Set<HealthMetric.ID>?
    private let defaults: UserDefaults

    private static let enabledKey = "observerSync.enabled"
    private static let lastSyncAtKey = "observerSync.lastSyncAt"
    private static let logsKey = "observerSync.logs"
    private static let anchorsKey = "observerSync.anchors"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.lastSyncAt = defaults.object(forKey: Self.lastSyncAtKey) as? Date
        if let data = defaults.data(forKey: Self.logsKey),
           let savedLogs = try? JSONDecoder().decode([HealthObserverLogEntry].self, from: data) {
            self.logs = savedLogs
        } else {
            self.logs = []
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.retryPendingSyncIfNeeded()
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            await refreshObservers()
        }
    }

    func configurationDidChange() {
        Task {
            await refreshObservers()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)

        if enabled {
            addLog(level: "info", message: "自动同步已开启")
            Task {
                await refreshObservers(force: true)
            }
        } else {
            stopObservers()
            statusText = "自动同步已关闭"
            activeConfigurationSignature = nil
            addLog(level: "info", message: "自动同步已关闭")
        }
    }

    func refreshObservers(force: Bool = false) async {
        guard isEnabled else {
            stopObservers()
            statusText = "自动同步已关闭"
            activeConfigurationSignature = nil
            return
        }

        let configurations = ConfigurationPersistence.load().filter(\.isReadyToSend)
        let types = Set(configurations.flatMap { $0.selectedMetrics.compactMap(\.sampleType) })
        let signature = configurationSignature(for: configurations)

        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "当前设备不支持 HealthKit 自动同步"
            addLog(level: "error", message: statusText)
            return
        }

        guard !types.isEmpty else {
            statusText = "没有可自动同步的健康指标"
            addLog(level: "warning", message: statusText)
            stopObservers()
            activeConfigurationSignature = nil
            return
        }

        if !force,
           !observerQueries.isEmpty,
           activeConfigurationSignature == signature {
            statusText = "HealthKit Observer 已保持注册"
            return
        }

        do {
            try await requestAuthorization(for: types)
            stopObservers()

            for type in types {
                registerObserver(for: type)
                try await enableBackgroundDelivery(for: type)
                try await initializeAnchorIfNeeded(for: type)
            }

            observedTypes = types
            activeConfigurationSignature = signature
            statusText = "已启动 HealthKit Observer 自动同步"
            addLog(level: "info", message: "已注册 \(types.count) 个 HealthKit Observer")
        } catch {
            statusText = "自动同步启动失败：\(error.localizedDescription)"
            addLog(level: "error", message: statusText)
        }
    }

    func syncNow(reason: String, changedMetricIDs: Set<HealthMetric.ID>? = nil) async {
        guard !isSyncing else { return }

        let configurations = ConfigurationPersistence.load()
            .filter(\.isReadyToSend)
            .filter { configuration in
                guard let changedMetricIDs else { return true }
                return !configuration.selectedMetricIDs.isDisjoint(with: changedMetricIDs)
            }
        guard !configurations.isEmpty else {
            await MainActor.run {
                statusText = "没有可发送的自动同步配置"
            }
            addLog(level: "warning", message: "触发自动同步但没有可发送配置")
            return
        }

        isSyncing = true
        await MainActor.run {
            statusText = "正在自动同步：\(reason)"
        }
        addLog(level: "info", message: "收到 HealthKit 更新：\(reason)")

        let backgroundTaskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "HealthObserverSync") {
                UIApplication.shared.endBackgroundTask(.invalid)
            }
        }

        defer {
            isSyncing = false
            Task { @MainActor in
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }

        for configuration in configurations {
            do {
                let result = try await exporter.send(
                    configuration: configuration,
                    shouldRequestAuthorization: false,
                    allowProtectedDataUnavailable: true
                )
                ConfigurationPersistence.markSent(id: configuration.id, status: "[自动] \(result)")
                await MainActor.run {
                    statusText = "[自动] \(configuration.name)：\(result)"
                    lastSyncAt = .now
                    defaults.set(lastSyncAt, forKey: Self.lastSyncAtKey)
                }
                addLog(level: "success", message: "\(configuration.name) 自动上传成功")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ConfigurationPersistence.markSent(id: configuration.id, status: "[自动] \(message)")
                await MainActor.run {
                    statusText = "[自动] \(configuration.name)：\(message)"
                }
                addLog(level: "error", message: "\(configuration.name) 自动上传失败：\(message)")
                if case .protectedHealthDataUnavailable = (error as? ExportError) {
                    pendingRetryReason = reason
                    pendingRetryMetricIDs = changedMetricIDs
                    addLog(level: "warning", message: "锁屏时健康数据不可读，已等待解锁后重试")
                }
            }
        }
    }

    private func registerObserver(for sampleType: HKSampleType) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self else {
                completionHandler()
                return
            }

            if let error {
                Task { @MainActor in
                    self.statusText = "Observer 错误：\(error.localizedDescription)"
                    self.addLog(level: "error", message: self.statusText)
                }
                completionHandler()
                return
            }

            Task {
                await self.handleObserverUpdate(for: sampleType)
                completionHandler()
            }
        }

        observerQueries.append(query)
        healthStore.execute(query)
    }

    private func stopObservers() {
        observerQueries.forEach { healthStore.stop($0) }
        observerQueries.removeAll()
        observedTypes.removeAll()
    }

    private func configurationSignature(for configurations: [ExportConfiguration]) -> String {
        configurations
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { configuration in
                let metrics = configuration.selectedMetricIDs.sorted().joined(separator: ",")
                return [
                    configuration.id.uuidString,
                    configuration.endpointURL,
                    configuration.bearerToken,
                    String(configuration.lookbackHours),
                    configuration.includeSamples ? "1" : "0",
                    metrics
                ].joined(separator: "|")
            }
            .joined(separator: "||")
    }

    private func addLog(level: String, message: String) {
        logs.insert(HealthObserverLogEntry(level: level, message: message), at: 0)
        logs = Array(logs.prefix(30))
        statusText = message
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: Self.logsKey)
        }
    }

    private func retryPendingSyncIfNeeded() async {
        guard let reason = pendingRetryReason else { return }
        let metricIDs = pendingRetryMetricIDs
        pendingRetryReason = nil
        pendingRetryMetricIDs = nil
        addLog(level: "info", message: "检测到解锁，重试自动同步")
        await syncNow(reason: reason, changedMetricIDs: metricIDs)
    }

    private func handleObserverUpdate(for sampleType: HKSampleType) async {
        do {
            let change = try await anchoredChange(for: sampleType, initializeIfNeeded: false)
            guard change.hasChanges else { return }
            addLog(level: "info", message: "收到 HealthKit 增量更新：\(sampleType.identifier)，新增 \(change.addedCount) 条")
            await syncNow(reason: sampleType.identifier, changedMetricIDs: changedMetricIDs(for: sampleType))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            addLog(level: "error", message: "增量查询失败：\(sampleType.identifier) - \(message)")
        }
    }

    private func changedMetricIDs(for sampleType: HKSampleType) -> Set<HealthMetric.ID> {
        Set(
            HealthMetric.allCases.compactMap { metric in
                guard metric.sampleType?.identifier == sampleType.identifier else { return nil }
                return metric.id
            }
        )
    }

    private func initializeAnchorIfNeeded(for sampleType: HKSampleType) async throws {
        guard anchor(for: sampleType) == nil else { return }
        _ = try await anchoredChange(for: sampleType, initializeIfNeeded: true)
        addLog(level: "info", message: "已初始化增量锚点：\(sampleType.identifier)")
    }

    private func anchoredChange(for sampleType: HKSampleType, initializeIfNeeded: Bool) async throws -> (addedCount: Int, deletedCount: Int, hasChanges: Bool) {
        let storedAnchor = anchor(for: sampleType)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: storedAnchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, deletedObjects, newAnchor, error in
                guard let self else {
                    continuation.resume(returning: (0, 0, false))
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let newAnchor {
                    self.save(anchor: newAnchor, for: sampleType)
                }

                let addedCount = samples?.count ?? 0
                let deletedCount = deletedObjects?.count ?? 0
                let hasChanges = initializeIfNeeded ? false : (addedCount > 0 || deletedCount > 0)
                continuation.resume(returning: (addedCount, deletedCount, hasChanges))
            }

            self.healthStore.execute(query)
        }
    }

    private func anchor(for sampleType: HKSampleType) -> HKQueryAnchor? {
        guard let data = anchorStore()[sampleType.identifier] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func save(anchor: HKQueryAnchor, for sampleType: HKSampleType) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        var store = anchorStore()
        store[sampleType.identifier] = data
        defaults.set(store, forKey: Self.anchorsKey)
    }

    private func anchorStore() -> [String: Data] {
        defaults.dictionary(forKey: Self.anchorsKey) as? [String: Data] ?? [:]
    }

    private func requestAuthorization(for types: Set<HKSampleType>) async throws {
        let requestStatus = try await requestStatus(for: types)
        guard requestStatus == .shouldRequest else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: types) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportError.healthDataUnavailable)
                }
            }
        }
    }

    private func requestStatus(for types: Set<HKSampleType>) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKAuthorizationRequestStatus, Error>) in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: types) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func enableBackgroundDelivery(for sampleType: HKSampleType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportError.invalidResponse)
                }
            }
        }
    }
}
