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

    func requestAuthorization(for configuration: ExportConfiguration) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ExportError.healthDataUnavailable
        }

        let types = Set(configuration.selectedMetrics.compactMap(\.sampleType))
        guard !types.isEmpty else {
            throw ExportError.noMetricsSelected
        }

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

        var metricPayloads: [[String: Any]] = []

        for metric in configuration.selectedMetrics {
            let payload = try await payload(for: metric, startDate: startDate, endDate: endDate, includeSamples: configuration.includeSamples)
            metricPayloads.append(payload)
        }

        return HealthExportPayload(
            configuration: configuration,
            generatedAt: endDate,
            startDate: startDate,
            endDate: endDate,
            metrics: metricPayloads
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

    private func payload(for metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> [String: Any] {
        switch metric {
        case .sleepAnalysis:
            return try await sleepPayload(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        case .workouts:
            return try await workoutsPayload(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        case .mindfulState:
            return try await stateOfMindPayload(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        default:
            return try await quantityPayload(metric: metric, startDate: startDate, endDate: endDate, includeSamples: includeSamples)
        }
    }

    private func quantityPayload(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> [String: Any] {
        guard let quantityType = metric.sampleType as? HKQuantityType, let unit = metric.unit else {
            return basePayload(metric: metric, value: NSNull(), unit: nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let options = statisticsOptions(for: metric)
        let statistics = try await statistics(for: quantityType, predicate: predicate, options: options)
        var payload = basePayload(metric: metric, value: NSNull(), unit: unit.unitString)

        if options.contains(.cumulativeSum), let sum = statistics.sumQuantity()?.doubleValue(for: unit) {
            payload["summary"] = ["sum": sum]
        } else {
            var summary: [String: Any] = [:]
            if let average = statistics.averageQuantity()?.doubleValue(for: unit) {
                summary["average"] = average
            }
            if let minimum = statistics.minimumQuantity()?.doubleValue(for: unit) {
                summary["minimum"] = minimum
            }
            if let maximum = statistics.maximumQuantity()?.doubleValue(for: unit) {
                summary["maximum"] = maximum
            }
            payload["summary"] = summary
        }

        if includeSamples {
            payload["samples"] = try await quantitySamples(for: quantityType, unit: unit, predicate: predicate)
        }

        return payload
    }

    private func sleepPayload(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> [String: Any] {
        guard let sleepType = metric.sampleType as? HKCategoryType else {
            return basePayload(metric: metric, value: NSNull(), unit: "minute")
        }

        let sleepStartDate = Calendar.current.date(byAdding: .hour, value: -12, to: startDate) ?? startDate
        let predicate = HKQuery.predicateForSamples(withStart: sleepStartDate, end: endDate, options: [])
        let samples = filteredSleepSamples(try await categorySamples(for: sleepType, predicate: predicate))
        var asleepMinutes = 0
        var records: [[String: Any]] = []
        let inBedMinutes = SleepMinuteMath.roundedUnionMinutes(
            from: samples
                .filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                .map { ($0.startDate, $0.endDate) }
        )

        for sample in samples {
            let roundedMinutes = SleepMinuteMath.roundedMinutes(from: sample.startDate, to: sample.endDate)
            let stage = sleepStageName(rawValue: sample.value)
            if isAsleepSleepStage(rawValue: sample.value) {
                asleepMinutes += roundedMinutes
            }

            records.append([
                "start_time": sample.startDate.iso8601String,
                "end_time": sample.endDate.iso8601String,
                "stage": stage,
                "duration_minutes": roundedMinutes
            ])
        }

        var payload = basePayload(metric: metric, value: NSNull(), unit: "minute")
        payload["summary"] = [
            "asleep_minutes": asleepMinutes,
            "in_bed_minutes": inBedMinutes,
            "record_count": samples.count
        ]
        if includeSamples {
            payload["samples"] = records
        }
        return payload
    }

    private func workoutsPayload(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> [String: Any] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let workouts = try await workouts(predicate: predicate)
        let totalDuration = workouts.reduce(0.0) { $0 + $1.duration / 60 }
        let totalEnergy = workouts.reduce(0.0) { partial, workout in
            partial + (workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
        }

        var payload = basePayload(metric: metric, value: NSNull(), unit: "minute")
        payload["summary"] = [
            "workout_count": workouts.count,
            "total_duration_minutes": totalDuration,
            "total_active_energy_kcal": totalEnergy
        ]
        if includeSamples {
            payload["samples"] = workouts.map { workout in
                [
                    "start_time": workout.startDate.iso8601String,
                    "end_time": workout.endDate.iso8601String,
                    "duration_minutes": workout.duration / 60,
                    "activity_type": workout.workoutActivityType.name,
                    "active_energy_kcal": workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) as Any
                ]
            }
        }
        return payload
    }

    private func sampleCountPayload(metric: HealthMetric, startDate: Date, endDate: Date) async throws -> [String: Any] {
        guard let sampleType = metric.sampleType else {
            return basePayload(metric: metric, value: NSNull(), unit: nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let count = try await sampleCount(for: sampleType, predicate: predicate)
        var payload = basePayload(metric: metric, value: NSNull(), unit: "count")
        payload["summary"] = ["record_count": count]
        return payload
    }

    private func stateOfMindPayload(metric: HealthMetric, startDate: Date, endDate: Date, includeSamples: Bool) async throws -> [String: Any] {
        guard #available(iOS 17.0, *), let sampleType = metric.sampleType else {
            return basePayload(metric: metric, value: NSNull(), unit: "valence")
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let samples = try await stateOfMindSamples(for: sampleType, predicate: predicate)
        let latestSample = samples.first
        let latestValence: Any = latestSample?.valence ?? NSNull()
        var payload = basePayload(metric: metric, value: latestValence, unit: "valence")

        if samples.isEmpty {
            payload["summary"] = ["record_count": 0]
            return payload
        }

        let valences = samples.map(\.valence)
        let averageValence = valences.reduce(0, +) / Double(valences.count)
        let minimumValence: Any = valences.min() ?? NSNull()
        let maximumValence: Any = valences.max() ?? NSNull()
        var summary: [String: Any] = [
            "record_count": samples.count,
            "latest_valence": latestValence,
            "average_valence": averageValence,
            "minimum_valence": minimumValence,
            "maximum_valence": maximumValence
        ]
        if let latestSample {
            summary["latest_kind"] = stateOfMindKindName(latestSample.kind)
            summary["latest_valence_classification"] = stateOfMindValenceClassificationName(latestSample.valenceClassification)
            summary["latest_labels"] = latestSample.labels.map(stateOfMindLabelName)
            summary["latest_associations"] = latestSample.associations.map(stateOfMindAssociationName)
        }
        payload["summary"] = summary

        if includeSamples {
            payload["samples"] = samples.map(stateOfMindRecord)
        }

        return payload
    }

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

    private func statistics(for quantityType: HKQuantityType, predicate: NSPredicate, options: HKStatisticsOptions) async throws -> HKStatistics {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let statistics {
                    continuation.resume(returning: statistics)
                } else {
                    continuation.resume(throwing: ExportError.invalidResponse)
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

    private func sampleCount(for sampleType: HKSampleType, predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.count ?? 0)
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

        return samples.filter { sample in
            sample.value != HKCategoryValueSleepAnalysis.asleep.rawValue
        }
    }

    private func isAsleepSleepStage(rawValue: Int) -> Bool {
        if rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue {
            return true
        }
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
        if rawValue == HKCategoryValueSleepAnalysis.inBed.rawValue {
            return "in_bed"
        }
        if rawValue == HKCategoryValueSleepAnalysis.awake.rawValue {
            return "awake"
        }
        if rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue {
            return "asleep"
        }
        if #available(iOS 16.0, *) {
            switch rawValue {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return "asleep_core"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return "asleep_deep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return "asleep_rem"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return "asleep_unspecified"
            default:
                break
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
        case 1: "amazed"
        case 2: "amused"
        case 3: "angry"
        case 4: "anxious"
        case 5: "ashamed"
        case 6: "brave"
        case 7: "calm"
        case 8: "content"
        case 9: "disappointed"
        case 10: "discouraged"
        case 11: "disgusted"
        case 12: "embarrassed"
        case 13: "excited"
        case 14: "frustrated"
        case 15: "grateful"
        case 16: "guilty"
        case 17: "happy"
        case 18: "hopeless"
        case 19: "irritated"
        case 20: "jealous"
        case 21: "joyful"
        case 22: "lonely"
        case 23: "passionate"
        case 24: "peaceful"
        case 25: "proud"
        case 26: "relieved"
        case 27: "sad"
        case 28: "scared"
        case 29: "stressed"
        case 30: "surprised"
        case 31: "worried"
        case 32: "annoyed"
        case 33: "confident"
        case 34: "drained"
        case 35: "hopeful"
        case 36: "indifferent"
        case 37: "overwhelmed"
        case 38: "satisfied"
        default: "unknown_\(label.rawValue)"
        }
    }

    @available(iOS 17.0, *)
    private func stateOfMindAssociationName(_ association: HKStateOfMind.Association) -> String {
        switch association.rawValue {
        case 1: "community"
        case 2: "current_events"
        case 3: "dating"
        case 4: "education"
        case 5: "family"
        case 6: "fitness"
        case 7: "friends"
        case 8: "health"
        case 9: "hobbies"
        case 10: "identity"
        case 11: "money"
        case 12: "partner"
        case 13: "self_care"
        case 14: "spirituality"
        case 15: "tasks"
        case 16: "travel"
        case 17: "work"
        case 18: "weather"
        default: "unknown_\(association.rawValue)"
        }
    }

}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: "running"
        case .walking: "walking"
        case .cycling: "cycling"
        case .traditionalStrengthTraining: "strength_training"
        case .functionalStrengthTraining: "functional_strength_training"
        case .highIntensityIntervalTraining: "hiit"
        case .yoga: "yoga"
        case .swimming: "swimming"
        case .mindAndBody: "mind_and_body"
        default: "activity_\(rawValue)"
        }
    }
}

enum SleepMinuteMath {
    static func roundedMinutes(from startDate: Date, to endDate: Date) -> Int {
        let minutes = endDate.timeIntervalSince(startDate) / 60
        return Int(minutes.rounded())
    }

    static func roundedUnionMinutes(from intervals: [(startDate: Date, endDate: Date)]) -> Int {
        let sortedIntervals = intervals
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        guard var current = sortedIntervals.first else {
            return 0
        }

        var minutes = 0
        for interval in sortedIntervals.dropFirst() {
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
