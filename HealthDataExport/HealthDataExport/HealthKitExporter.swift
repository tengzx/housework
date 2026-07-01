import Foundation
import HealthKit
import UIKit

enum ExportError: LocalizedError {
    case healthDataUnavailable
    case invalidEndpoint
    case noMetricsSelected
    case httpFailure(Int, String)
    case invalidResponse
    case invalidPreview
    case protectedHealthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "当前设备不支持 HealthKit，需在 iPhone 真机上运行。"
        case .invalidEndpoint:
            "接口地址无效。"
        case .noMetricsSelected:
            "至少需要选择一个健康指标。"
        case let .httpFailure(code, body):
            "接口返回 HTTP \(code)：\(body)"
        case .invalidResponse:
            "接口没有返回有效 HTTP 响应。"
        case .invalidPreview:
            "预览 JSON 生成失败。"
        case .protectedHealthDataUnavailable:
            "手机锁屏时受保护的健康数据不可读取，请解锁后再运行快捷指令。"
        }
    }
}

final class HealthKitExporter {
    private let healthStore = HKHealthStore()

    // Maps HealthMetric id → (backend metric name, unit) for the events direct path.
    private static let eventMetricMap: [HealthMetric: (metric: String, unit: String)] = [
        .hrvSDNN:        ("hrv_sdnn",               "ms"),
        .restingHeartRate: ("resting_heart_rate",   "bpm"),
        .activeEnergyBurned: ("active_energy",      "kcal"),
        .exerciseTime:   ("exercise_minutes",        "min"),
        .stepCount:      ("step_count",              "count"),
        .respiratoryRate: ("respiratory_rate",       "count/min"),
        .bloodOxygen:    ("blood_oxygen",            "%"),
        .wristTemperature: ("wrist_temperature_delta", "degC"),
    ]

    // Holds both the raw metrics block and the structured entries for one metric.
    private struct MetricPayloadResult {
        var block: [String: Any]
        var events: [[String: Any]] = []
        var heartRateSamples: [[String: Any]] = []
        var sleepSessions: [[String: Any]] = []
        var workoutSessions: [[String: Any]] = []
        var stateOfMindEntries: [[String: Any]] = []
    }

    func requestAuthorization(for configuration: ExportConfiguration) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ExportError.healthDataUnavailable
        }

        let types = Set(configuration.selectedMetrics.compactMap(\.sampleType))
        guard !types.isEmpty else {
            throw ExportError.noMetricsSelected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: types) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func buildPayload(for configuration: ExportConfiguration, allowProtectedDataUnavailable: Bool = false) async throws -> HealthExportPayload {
        if !allowProtectedDataUnavailable {
            let isProtectedDataAvailable = await MainActor.run {
                UIApplication.shared.isProtectedDataAvailable
            }
            guard isProtectedDataAvailable else {
                throw ExportError.protectedHealthDataUnavailable
            }
        }
        guard !configuration.selectedMetrics.isEmpty else {
            throw ExportError.noMetricsSelected
        }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -configuration.lookbackHours, to: endDate) ?? endDate.addingTimeInterval(-86_400)

        var metricBlocks: [[String: Any]] = []
        var allEvents: [[String: Any]] = []
        var allHeartRateSamples: [[String: Any]] = []
        var allSleepSessions: [[String: Any]] = []
        var allWorkouts: [[String: Any]] = []
        var allStateOfMindEntries: [[String: Any]] = []

        for metric in configuration.selectedMetrics {
            do {
                let result = try await metricResult(for: metric, startDate: startDate, endDate: endDate, includeSamples: configuration.includeSamples)
                metricBlocks.append(result.block)
                allEvents.append(contentsOf: result.events)
                allHeartRateSamples.append(contentsOf: result.heartRateSamples)
                allSleepSessions.append(contentsOf: result.sleepSessions)
                allWorkouts.append(contentsOf: result.workoutSessions)
                allStateOfMindEntries.append(contentsOf: result.stateOfMindEntries)
            } catch {
                var errBlock = basePayload(metric: metric, value: NSNull(), unit: metric.unit?.unitString)
                errBlock["error"] = error.localizedDescription
                metricBlocks.append(errBlock)
            }
        }

        return HealthExportPayload(
            configuration: configuration,
            generatedAt: endDate,
            startDate: startDate,
            endDate: endDate,
            metrics: metricBlocks,
            events: allEvents,
            heartRateSamples: allHeartRateSamples,
            sleepSessions: allSleepSessions,
            workouts: allWorkouts,
            stateOfMindEntries: allStateOfMindEntries
        )
    }

    func send(configuration: ExportConfiguration, shouldRequestAuthorization: Bool = true, allowProtectedDataUnavailable: Bool = false) async throws -> String {
        if shouldRequestAuthorization {
            try await self.requestAuthorization(for: configuration)
        }
        let payload = try await buildPayload(for: configuration, allowProtectedDataUnavailable: allowProtectedDataUnavailable)
        return try await send(payload: payload)
    }

    func send(payload: HealthExportPayload) async throws -> String {
        let configuration = payload.configuration
        guard let url = URL(string: configuration.endpointURL), url.scheme?.hasPrefix("http") == true else {
            throw ExportError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !configuration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try payload.jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExportError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ExportError.httpFailure(httpResponse.statusCode, responseBody)
        }

        return "发送成功，HTTP \(httpResponse.statusCode)，\(payload.itemCount) 条数据"
    }

    // MARK: - Metric dispatch

    private func metricResult(for metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> MetricPayloadResult {
        switch metric {
        case .sleepAnalysis:
            return try await sleepResult(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        case .workouts:
            return try await workoutsResult(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        case .mindfulState:
            return try await stateOfMindResult(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        default:
            return try await quantityResult(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        }
    }

    // MARK: - Quantity metrics (HRV, HR, step count, etc.)

    private func quantityResult(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> MetricPayloadResult {
        guard let quantityType = metric.sampleType as? HKQuantityType, let unit = metric.unit else {
            return MetricPayloadResult(block: basePayload(metric: metric, value: NSNull(), unit: nil))
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let options = statisticsOptions(for: metric)
        let samples = try await quantitySamples(for: quantityType, unit: unit, predicate: predicate)

        let latestValue: Any = samples.first?["value"] ?? NSNull()
        var block = basePayload(metric: metric, value: latestValue, unit: unit.unitString)

        let statistics = try await statistics(for: quantityType, predicate: predicate, options: options)
        if let statistics {
            if options.contains(.cumulativeSum), let sum = statistics.sumQuantity()?.doubleValue(for: unit) {
                block["summary"] = ["sum": sum, "sample_count": samples.count]
            } else {
                var summary: [String: Any] = ["sample_count": samples.count]
                if let avg = statistics.averageQuantity()?.doubleValue(for: unit) { summary["average"] = avg }
                if let min = statistics.minimumQuantity()?.doubleValue(for: unit) { summary["minimum"] = min }
                if let max = statistics.maximumQuantity()?.doubleValue(for: unit) { summary["maximum"] = max }
                block["summary"] = summary
            }
        }

        if includeSamples { block["samples"] = samples }

        var result = MetricPayloadResult(block: block)

        if metric == .heartRate {
            result.heartRateSamples = samples.compactMap { buildHeartRateSample(from: $0) }
        } else if let mapping = Self.eventMetricMap[metric] {
            result.events = samples.compactMap { buildMetricEvent(from: $0, metric: metric, mapping: mapping) }
        }

        return result
    }

    // MARK: - Sleep

    private func sleepResult(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> MetricPayloadResult {
        guard let sleepType = metric.sampleType as? HKCategoryType else {
            return MetricPayloadResult(block: basePayload(metric: metric, value: NSNull(), unit: "minute"))
        }

        // Extend lookback by 12 h to catch sleep that started before the window.
        let sleepStartDate = Calendar.current.date(byAdding: .hour, value: -12, to: startDate) ?? startDate
        let predicate = HKQuery.predicateForSamples(withStart: sleepStartDate, end: endDate, options: [])
        let allSamples = filteredSleepSamples(try await categorySamples(for: sleepType, predicate: predicate))

        var asleepMinutes = 0
        var records: [[String: Any]] = []
        let inBedMinutes = SleepMinuteMath.roundedUnionMinutes(
            from: allSamples
                .filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                .map { ($0.startDate, $0.endDate) }
        )

        for sample in allSamples {
            let mins = SleepMinuteMath.roundedMinutes(from: sample.startDate, to: sample.endDate)
            let stage = sleepStageName(rawValue: sample.value)
            if isAsleepSleepStage(rawValue: sample.value) { asleepMinutes += mins }
            records.append([
                "start_time": sample.startDate.iso8601String,
                "end_time": sample.endDate.iso8601String,
                "stage": stage,
                "duration_minutes": mins
            ])
        }

        var block = basePayload(metric: metric, value: asleepMinutes, unit: "minute")
        block["summary"] = ["asleep_minutes": asleepMinutes, "in_bed_minutes": inBedMinutes, "record_count": allSamples.count]
        if includeSamples { block["samples"] = records }

        var result = MetricPayloadResult(block: block)
        let clusters = clusterSleepSamples(allSamples)
        result.sleepSessions = clusters.enumerated().compactMap { idx, cluster in
            buildSleepSessionEntry(from: cluster, index: idx + 1)
        }
        return result
    }

    // MARK: - Workouts

    private func workoutsResult(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> MetricPayloadResult {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let hkWorkouts = try await workouts(predicate: predicate)
        let totalDuration = hkWorkouts.reduce(0.0) { $0 + $1.duration / 60 }
        let totalEnergy = hkWorkouts.reduce(0.0) { sum, w in
            sum + (w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
        }

        var block = basePayload(metric: metric, value: hkWorkouts.count, unit: "minute")
        block["summary"] = [
            "workout_count": hkWorkouts.count,
            "total_duration_minutes": totalDuration,
            "total_active_energy_kcal": totalEnergy
        ]
        if includeSamples {
            block["samples"] = hkWorkouts.map { w -> [String: Any] in
                var s: [String: Any] = [
                    "start_time": w.startDate.iso8601String,
                    "end_time": w.endDate.iso8601String,
                    "duration_minutes": w.duration / 60,
                    "activity_type": w.workoutActivityType.name
                ]
                if let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                    s["active_energy_kcal"] = kcal
                }
                return s
            }
        }

        var result = MetricPayloadResult(block: block)
        result.workoutSessions = hkWorkouts.map { buildWorkoutEntry(from: $0) }
        return result
    }

    // MARK: - State of Mind

    private func stateOfMindResult(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> MetricPayloadResult {
        guard #available(iOS 17.0, *), let sampleType = metric.sampleType else {
            return MetricPayloadResult(block: basePayload(metric: metric, value: NSNull(), unit: "valence"))
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let samples = try await stateOfMindSamples(for: sampleType, predicate: predicate)
        let latestSample = samples.first
        let latestValence: Any = latestSample?.valence ?? NSNull()
        var block = basePayload(metric: metric, value: latestValence, unit: "valence")

        if samples.isEmpty {
            block["summary"] = ["record_count": 0]
            return MetricPayloadResult(block: block)
        }

        let valences = samples.map(\.valence)
        let avgValence = valences.reduce(0, +) / Double(valences.count)
        var summary: [String: Any] = [
            "record_count": samples.count,
            "latest_valence": latestValence,
            "average_valence": avgValence,
            "minimum_valence": valences.min() as Any,
            "maximum_valence": valences.max() as Any
        ]
        if let s = latestSample {
            summary["latest_kind"] = stateOfMindKindName(s.kind)
            summary["latest_valence_classification"] = stateOfMindValenceClassificationName(s.valenceClassification)
            summary["latest_labels"] = s.labels.map(stateOfMindLabelName)
            summary["latest_associations"] = s.associations.map(stateOfMindAssociationName)
        }
        block["summary"] = summary

        if includeSamples { block["samples"] = samples.map(stateOfMindRecord) }

        var result = MetricPayloadResult(block: block)
        if #available(iOS 17.0, *) {
            result.stateOfMindEntries = samples.map { buildStateOfMindEntry(from: $0) }
        }
        return result
    }

    // MARK: - Structured entry builders

    private func buildMetricEvent(from sample: [String: Any], metric: HealthMetric, mapping: (metric: String, unit: String)) -> [String: Any]? {
        guard let startTime = sample["start_time"] as? String,
              let endTime = sample["end_time"] as? String,
              let value = sample["value"] as? Double else { return nil }
        return [
            "external_id": "\(metric.id)_\(startTime)_\(endTime)",
            "metric": mapping.metric,
            "value": value,
            "unit": mapping.unit,
            "start_time": startTime,
            "end_time": endTime,
            "recorded_at": endTime,
            "sample_type": metric.id,
            "source_name": "HealthDataExport"
        ]
    }

    private func buildHeartRateSample(from sample: [String: Any]) -> [String: Any]? {
        guard let endTime = sample["end_time"] as? String,
              let bpm = sample["value"] as? Double else { return nil }
        let startTime = sample["start_time"] as? String ?? endTime
        return [
            "external_id": "heartRate_\(startTime)_\(endTime)",
            "sample_time": endTime,
            "bpm": bpm,
            "source_name": "HealthDataExport"
        ]
    }

    private func clusterSleepSamples(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        guard let first = sorted.first else { return [] }

        var clusters: [[HKCategorySample]] = []
        var current: [HKCategorySample] = [first]
        var clusterEnd = first.endDate

        for sample in sorted.dropFirst() {
            if sample.startDate.timeIntervalSince(clusterEnd) > 6 * 3600 {
                clusters.append(current)
                current = []
                clusterEnd = sample.endDate
            } else {
                clusterEnd = max(clusterEnd, sample.endDate)
            }
            current.append(sample)
        }
        clusters.append(current)
        return clusters
    }

    private func buildSleepSessionEntry(from cluster: [HKCategorySample], index: Int) -> [String: Any]? {
        guard let sessionStart = cluster.min(by: { $0.startDate < $1.startDate })?.startDate,
              let sessionEnd = cluster.max(by: { $0.endDate < $1.endDate })?.endDate else { return nil }

        var asleep = 0, awake = 0, deep = 0, rem = 0, core = 0
        var stages: [[String: Any]] = []
        var allIntervals: [(startDate: Date, endDate: Date)] = []

        for sample in cluster {
            let mins = SleepMinuteMath.roundedMinutes(from: sample.startDate, to: sample.endDate)
            let rawStage = sleepStageName(rawValue: sample.value)
            guard let backendStage = sleepStageToBackend(rawStage) else { continue }
            stages.append([
                "stage": backendStage,
                "start_time": sample.startDate.iso8601String,
                "end_time": sample.endDate.iso8601String,
                "minutes": mins
            ])
            allIntervals.append((startDate: sample.startDate, endDate: sample.endDate))
            switch backendStage {
            case "deep":   deep += mins;  asleep += mins
            case "rem":    rem += mins;   asleep += mins
            case "core", "asleep": core += mins; asleep += mins
            case "awake":  awake += mins
            default: break
            }
        }

        // Use union of all sample intervals to avoid double-counting when inBed and
        // stage samples overlap (Apple Watch writes both for the same time window).
        let inBed = SleepMinuteMath.roundedUnionMinutes(from: allIntervals)

        if asleep == 0 { asleep = max(SleepMinuteMath.roundedMinutes(from: sessionStart, to: sessionEnd), 0) }

        var entry: [String: Any] = [
            "external_id": "sleepAnalysis_\(sessionStart.iso8601String)_\(index)",
            "session_type": "main_sleep",
            "start_time": sessionStart.iso8601String,
            "end_time": sessionEnd.iso8601String,
            "in_bed_minutes": inBed,
            "asleep_minutes": asleep,
            "sleep_stage_count": stages.count,
            "sample_type": "sleepAnalysis",
            "source_name": "HealthDataExport",
            "sleep_stages": stages
        ]
        if awake > 0 { entry["awake_minutes"] = awake }
        if deep > 0  { entry["deep_minutes"]  = deep }
        if rem > 0   { entry["rem_minutes"]   = rem }
        if core > 0  { entry["core_minutes"]  = core }
        return entry
    }

    private func sleepStageToBackend(_ stage: String) -> String? {
        switch stage {
        case "in_bed":            "in_bed"
        case "asleep":            "asleep"
        case "awake":             "awake"
        case "asleep_core":       "core"
        case "asleep_deep":       "deep"
        case "asleep_rem":        "rem"
        case "asleep_unspecified": "asleep"
        default:                  nil
        }
    }

    private func buildWorkoutEntry(from workout: HKWorkout) -> [String: Any] {
        let durationSec = Int(workout.duration.rounded())
        var entry: [String: Any] = [
            "external_id": "workout_\(workout.startDate.iso8601String)_\(workout.endDate.iso8601String)",
            "workout_type": workout.workoutActivityType.backendTypeName,
            "start_time": workout.startDate.iso8601String,
            "end_time": workout.endDate.iso8601String,
            "duration_seconds": durationSec,
            "source_name": "HealthDataExport"
        ]
        if let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
            entry["active_energy_kcal"] = kcal
        }
        return entry
    }

    @available(iOS 17.0, *)
    private func buildStateOfMindEntry(from sample: HKStateOfMind) -> [String: Any] {
        // Map valence (-1…+1) to a 0–10 mood score.
        let moodScore = Int(round((sample.valence + 1.0) * 5.0))
        let energyColor: String
        if sample.valence > 0.33 {
            energyColor = "green"
        } else if sample.valence > -0.33 {
            energyColor = "yellow"
        } else {
            energyColor = "red"
        }
        return [
            "external_id": "stateOfMind_\(sample.startDate.iso8601String)",
            "recorded_at": sample.startDate.iso8601String,
            "mood_score": moodScore,
            "energy_color": energyColor,
            "tags": sample.labels.map(stateOfMindLabelName),
            "raw_payload_json": [
                "valence": sample.valence,
                "valence_classification": stateOfMindValenceClassificationName(sample.valenceClassification),
                "kind": stateOfMindKindName(sample.kind),
                "labels": sample.labels.map(stateOfMindLabelName),
                "associations": sample.associations.map(stateOfMindAssociationName)
            ]
        ]
    }

    // MARK: - HealthKit query helpers

    private func statisticsOptions(for metric: HealthMetric) -> HKStatisticsOptions {
        switch metric {
        case .activeEnergyBurned, .exerciseTime, .stepCount:
            [.cumulativeSum]
        case .heartRate:
            [.discreteAverage, .discreteMin, .discreteMax]
        default:
            [.discreteAverage, .discreteMin, .discreteMax]
        }
    }

    private func statistics(for quantityType: HKQuantityType, predicate: NSPredicate, options: HKStatisticsOptions) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(returning: statistics)
                }
            }
            healthStore.execute(query)
        }
    }

    private func quantitySamples(for quantityType: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async throws -> [[String: Any]] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map { sample in
                    [
                        "start_time": sample.startDate.iso8601String,
                        "end_time": sample.endDate.iso8601String,
                        "value": sample.quantity.doubleValue(for: unit)
                    ] as [String: Any]
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(for categoryType: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: categoryType, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    @available(iOS 17.0, *)
    private func stateOfMindSamples(for sampleType: HKSampleType, predicate: NSPredicate) async throws -> [HKStateOfMind] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKStateOfMind] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func workouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func basePayload(metric: HealthMetric, value: Any, unit: String?) -> [String: Any] {
        [
            "id": metric.id,
            "name": metric.title,
            "priority": metric.priority.rawValue,
            "unit": unit as Any,
            "value": value
        ]
    }

    private func filteredSleepSamples(_ samples: [HKCategorySample]) -> [HKCategorySample] {
        guard SleepSampleFilter.shouldDropGenericAsleep(from: samples.map(\.value)) else {
            return samples
        }
        return samples.filter { $0.value != HKCategoryValueSleepAnalysis.asleep.rawValue }
    }

    private func isAsleepSleepStage(rawValue: Int) -> Bool {
        if rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue { return true }
        if #available(iOS 16.0, *) {
            return [
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            ].contains(rawValue)
        }
        return false
    }

    private func sleepStageName(rawValue: Int) -> String {
        if rawValue == HKCategoryValueSleepAnalysis.inBed.rawValue  { return "in_bed" }
        if rawValue == HKCategoryValueSleepAnalysis.awake.rawValue  { return "awake" }
        if rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue { return "asleep" }
        if #available(iOS 16.0, *) {
            switch rawValue {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:        return "asleep_core"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:        return "asleep_deep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:         return "asleep_rem"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return "asleep_unspecified"
            default: break
            }
        }
        return "unknown"
    }

    @available(iOS 17.0, *)
    private func stateOfMindRecord(_ sample: HKStateOfMind) -> [String: Any] {
        [
            "start_time": sample.startDate.iso8601String,
            "end_time": sample.endDate.iso8601String,
            "value": sample.valence,
            "valence": sample.valence,
            "valence_classification": stateOfMindValenceClassificationName(sample.valenceClassification),
            "kind": stateOfMindKindName(sample.kind),
            "labels": sample.labels.map(stateOfMindLabelName),
            "associations": sample.associations.map(stateOfMindAssociationName)
        ]
    }

    @available(iOS 17.0, *)
    private func stateOfMindKindName(_ kind: HKStateOfMind.Kind) -> String {
        switch kind.rawValue {
        case 1: "momentary_emotion"
        case 2: "daily_mood"
        default: "unknown_\(kind.rawValue)"
        }
    }

    @available(iOS 17.0, *)
    private func stateOfMindValenceClassificationName(_ classification: HKStateOfMind.ValenceClassification) -> String {
        switch classification.rawValue {
        case 1: "very_unpleasant"
        case 2: "unpleasant"
        case 3: "slightly_unpleasant"
        case 4: "neutral"
        case 5: "slightly_pleasant"
        case 6: "pleasant"
        case 7: "very_pleasant"
        default: "unknown_\(classification.rawValue)"
        }
    }

    @available(iOS 17.0, *)
    private func stateOfMindLabelName(_ label: HKStateOfMind.Label) -> String {
        switch label.rawValue {
        case 1: "amazed";       case 2: "amused";        case 3: "angry"
        case 4: "anxious";      case 5: "ashamed";       case 6: "brave"
        case 7: "calm";         case 8: "content";       case 9: "disappointed"
        case 10: "discouraged"; case 11: "disgusted";    case 12: "embarrassed"
        case 13: "excited";     case 14: "frustrated";   case 15: "grateful"
        case 16: "guilty";      case 17: "happy";        case 18: "hopeless"
        case 19: "irritated";   case 20: "jealous";      case 21: "joyful"
        case 22: "lonely";      case 23: "passionate";   case 24: "peaceful"
        case 25: "proud";       case 26: "relieved";     case 27: "sad"
        case 28: "scared";      case 29: "stressed";     case 30: "surprised"
        case 31: "worried";     case 32: "annoyed";      case 33: "confident"
        case 34: "drained";     case 35: "hopeful";      case 36: "indifferent"
        case 37: "overwhelmed"; case 38: "satisfied"
        default: "unknown_\(label.rawValue)"
        }
    }

    @available(iOS 17.0, *)
    private func stateOfMindAssociationName(_ association: HKStateOfMind.Association) -> String {
        switch association.rawValue {
        case 1: "community";   case 2: "current_events"; case 3: "dating"
        case 4: "education";   case 5: "family";          case 6: "fitness"
        case 7: "friends";     case 8: "health";          case 9: "hobbies"
        case 10: "identity";   case 11: "money";          case 12: "partner"
        case 13: "self_care";  case 14: "spirituality";   case 15: "tasks"
        case 16: "travel";     case 17: "work";           case 18: "weather"
        default: "unknown_\(association.rawValue)"
        }
    }
}

// MARK: - HKWorkoutActivityType extensions

extension HKWorkoutActivityType {
    // Name used in the legacy metrics.samples path (kept for backward compat)
    var name: String {
        switch self {
        case .running:                       "running"
        case .walking:                       "walking"
        case .cycling:                       "cycling"
        case .traditionalStrengthTraining:   "strength_training"
        case .functionalStrengthTraining:    "functional_strength_training"
        case .highIntensityIntervalTraining: "hiit"
        case .yoga:                          "yoga"
        case .swimming:                      "swimming"
        case .mindAndBody:                   "mind_and_body"
        default: "activity_\(rawValue)"
        }
    }

    // Name used in the direct workouts path — must match backend APPLE_WORKOUT_TYPE_MAP values.
    var backendTypeName: String {
        switch self {
        case .running:                       "running"
        case .walking:                       "walking"
        case .cycling:                       "cycling"
        case .traditionalStrengthTraining:   "traditional_strength_training"
        case .functionalStrengthTraining:    "functional_strength_training"
        case .highIntensityIntervalTraining: "hiit"
        case .yoga:                          "yoga"
        case .swimming:                      "swimming"
        case .mindAndBody:                   "mind_and_body"
        default: "other"
        }
    }
}

// MARK: - Sleep helpers

enum SleepMinuteMath {
    static func roundedMinutes(from startDate: Date, to endDate: Date) -> Int {
        let minutes = endDate.timeIntervalSince(startDate) / 60
        return Int(minutes.rounded())
    }

    static func roundedUnionMinutes(from intervals: [(startDate: Date, endDate: Date)]) -> Int {
        let sorted = intervals
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        guard var current = sorted.first else { return 0 }

        var minutes = 0
        for interval in sorted.dropFirst() {
            if interval.startDate <= current.endDate {
                current.endDate = max(current.endDate, interval.endDate)
            } else {
                minutes += roundedMinutes(from: current.startDate, to: current.endDate)
                current = interval
            }
        }
        minutes += roundedMinutes(from: current.startDate, to: current.endDate)
        return minutes
    }
}

enum SleepSampleFilter {
    static func shouldDropGenericAsleep(from values: [Int]) -> Bool {
        if #available(iOS 16.0, *) {
            let detailedValues = [
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            ]
            return values.contains(where: detailedValues.contains)
        }
        return false
    }
}
