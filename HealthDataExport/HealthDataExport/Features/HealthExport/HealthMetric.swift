import Foundation
import HealthKit
import SwiftUI

enum HealthMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case sleepAnalysis
    case hrvSDNN
    case restingHeartRate
    case heartRate
    case activeEnergyBurned
    case exerciseTime
    case workouts
    case stepCount
    case respiratoryRate
    case bloodOxygen
    case wristTemperature
    case mindfulState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepAnalysis: L10n.tr("health_export.metric.sleep_analysis.title")
        case .hrvSDNN: L10n.tr("health_export.metric.hrv_sdnn.title")
        case .restingHeartRate: L10n.tr("health_export.metric.resting_heart_rate.title")
        case .heartRate: L10n.tr("health_export.metric.heart_rate.title")
        case .activeEnergyBurned: L10n.tr("health_export.metric.active_energy_burned.title")
        case .exerciseTime: L10n.tr("health_export.metric.exercise_time.title")
        case .workouts: L10n.tr("health_export.metric.workouts.title")
        case .stepCount: L10n.tr("health_export.metric.step_count.title")
        case .respiratoryRate: L10n.tr("health_export.metric.respiratory_rate.title")
        case .bloodOxygen: L10n.tr("health_export.metric.blood_oxygen.title")
        case .wristTemperature: L10n.tr("health_export.metric.wrist_temperature.title")
        case .mindfulState: L10n.tr("health_export.metric.mindful_state.title")
        }
    }

    var subtitle: String {
        switch self {
        case .sleepAnalysis: L10n.tr("health_export.metric.sleep_analysis.subtitle")
        case .hrvSDNN: L10n.tr("health_export.metric.hrv_sdnn.subtitle")
        case .restingHeartRate: L10n.tr("health_export.metric.resting_heart_rate.subtitle")
        case .heartRate: L10n.tr("health_export.metric.heart_rate.subtitle")
        case .activeEnergyBurned: L10n.tr("health_export.metric.active_energy_burned.subtitle")
        case .exerciseTime: L10n.tr("health_export.metric.exercise_time.subtitle")
        case .workouts: L10n.tr("health_export.metric.workouts.subtitle")
        case .stepCount: L10n.tr("health_export.metric.step_count.subtitle")
        case .respiratoryRate: L10n.tr("health_export.metric.respiratory_rate.subtitle")
        case .bloodOxygen: L10n.tr("health_export.metric.blood_oxygen.subtitle")
        case .wristTemperature: L10n.tr("health_export.metric.wrist_temperature.subtitle")
        case .mindfulState: L10n.tr("health_export.metric.mindful_state.subtitle")
        }
    }

    var symbolName: String {
        switch self {
        case .sleepAnalysis: "bed.double.fill"
        case .hrvSDNN: "waveform.path.ecg"
        case .restingHeartRate: "heart.circle.fill"
        case .heartRate: "heart.fill"
        case .activeEnergyBurned: "flame.fill"
        case .exerciseTime: "figure.run"
        case .workouts: "dumbbell.fill"
        case .stepCount: "shoeprints.fill"
        case .respiratoryRate: "lungs.fill"
        case .bloodOxygen: "drop.fill"
        case .wristTemperature: "thermometer.medium"
        case .mindfulState: "brain.head.profile"
        }
    }

    var priority: MetricPriority {
        switch self {
        case .sleepAnalysis, .hrvSDNN, .restingHeartRate, .heartRate, .activeEnergyBurned, .exerciseTime, .workouts:
            .primary
        case .stepCount, .respiratoryRate, .bloodOxygen, .wristTemperature:
            .secondary
        case .mindfulState:
            .subjective
        }
    }

    var sampleType: HKSampleType? {
        switch self {
        case .sleepAnalysis:
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .hrvSDNN:
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate:
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .heartRate:
            HKObjectType.quantityType(forIdentifier: .heartRate)
        case .activeEnergyBurned:
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exerciseTime:
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .workouts:
            HKObjectType.workoutType()
        case .stepCount:
            HKObjectType.quantityType(forIdentifier: .stepCount)
        case .respiratoryRate:
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .bloodOxygen:
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .wristTemperature:
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)
        case .mindfulState:
            if #available(iOS 17.0, *) {
                HKObjectType.stateOfMindType()
            } else {
                nil
            }
        }
    }

    var unit: HKUnit? {
        switch self {
        case .hrvSDNN:
            HKUnit.secondUnit(with: .milli)
        case .restingHeartRate, .heartRate:
            HKUnit.count().unitDivided(by: .minute())
        case .activeEnergyBurned:
            HKUnit.kilocalorie()
        case .exerciseTime:
            HKUnit.minute()
        case .stepCount:
            HKUnit.count()
        case .respiratoryRate:
            HKUnit.count().unitDivided(by: .minute())
        case .bloodOxygen:
            HKUnit.percent()
        case .wristTemperature:
            HKUnit.degreeCelsius()
        case .sleepAnalysis, .workouts, .mindfulState:
            nil
        }
    }
}

enum MetricPriority: String, CaseIterable, Identifiable {
    case primary
    case secondary
    case subjective

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary:
            return L10n.tr("health_export.metric_priority.primary")
        case .secondary:
            return L10n.tr("health_export.metric_priority.secondary")
        case .subjective:
            return L10n.tr("health_export.metric_priority.subjective")
        }
    }
}
