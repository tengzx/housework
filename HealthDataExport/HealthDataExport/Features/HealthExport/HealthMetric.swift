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
        case .sleepAnalysis: "Sleep Analysis"
        case .hrvSDNN: "HRV SDNN"
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRate: "Heart Rate"
        case .activeEnergyBurned: "Active Energy Burned"
        case .exerciseTime: "Exercise Time"
        case .workouts: "Workouts"
        case .stepCount: "Step Count"
        case .respiratoryRate: "Respiratory Rate"
        case .bloodOxygen: "Blood Oxygen"
        case .wristTemperature: "Wrist Temperature"
        case .mindfulState: "State of Mind"
        }
    }

    var subtitle: String {
        switch self {
        case .sleepAnalysis: "总睡眠、在床、睡眠分段"
        case .hrvSDNN: "恢复状态核心输入"
        case .restingHeartRate: "静息心率与恢复压力"
        case .heartRate: "日内心率平均与峰值"
        case .activeEnergyBurned: "活动消耗"
        case .exerciseTime: "运动分钟数"
        case .workouts: "训练记录"
        case .stepCount: "步数"
        case .respiratoryRate: "呼吸频率"
        case .bloodOxygen: "血氧"
        case .wristTemperature: "手腕温度变化"
        case .mindfulState: "Apple Health 情绪状态记录"
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
    case primary = "第一优先级"
    case secondary = "第二优先级"
    case subjective = "主观数据"

    var id: String { rawValue }
}
