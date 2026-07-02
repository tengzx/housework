import Foundation

enum ExerciseTrackingDisplay {
    static func isDistanceBased(_ trackingType: String) -> Bool {
        trackingType == "distance_time" || trackingType == "cardio"
    }

    static func isTimeBased(_ trackingType: String) -> Bool {
        trackingType == "time_only" || isDistanceBased(trackingType)
    }

    static func showsSecondColumn(_ trackingType: String) -> Bool {
        trackingType == "weight_reps" || isDistanceBased(trackingType)
    }

    static func secondColumnLabel(_ trackingType: String) -> String {
        isDistanceBased(trackingType) ? "米" : "KG"
    }

    static func thirdColumnLabel(_ trackingType: String) -> String {
        isTimeBased(trackingType) ? "时间" : "次数"
    }
}

// MARK: - Dashboard models

struct FitnessDashboardResponse: Decodable {
    let periodDays: Int
    let muscleVolume: [MuscleVolumeItem]
    let strengthProgress: StrengthProgress
    let templates: [FitnessTemplateSummary]
}

struct MuscleVolumeItem: Decodable {
    let muscleGroupId: Int
    let muscleGroupName: String
    let volumeKg: Double
}

struct StrengthProgress: Decodable {
    let hasData: Bool
    let items: [StrengthProgressItem]
}

struct StrengthProgressItem: Decodable, Identifiable {
    let exerciseId: Int
    let exerciseName: String
    let currentEstimated1Rm: Double
    let previousEstimated1Rm: Double
    let changePercent: Double
    var id: Int { exerciseId }
}

struct FitnessStrengthVolumeResponse: Decodable {
    let periodDays: Int
    let scope: String
    let totalVolumeKg: Double
    let regions: [FitnessStrengthVolumeRegion]
    let muscles: [FitnessStrengthVolumeMuscle]
}

struct FitnessStrengthVolumeRegion: Decodable, Identifiable {
    let regionCode: String
    let regionName: String
    let volumeKg: Double
    var id: String { regionCode }
}

struct FitnessStrengthVolumeMuscle: Decodable, Identifiable {
    let muscleGroupId: Int
    let muscleGroupCode: String
    let muscleGroupName: String
    let regionCode: String
    let regionName: String
    let volumeKg: Double
    var id: Int { muscleGroupId }
}

// MARK: - Template models

struct FitnessTemplateSummary: Decodable, Identifiable {
    let id: Int
    let name: String
    let trainingTheme: String?
    let exerciseCount: Int
    let setCount: Int
    let estimatedVolumeKg: Double
    let updatedAt: Date?
}

struct FitnessTemplateCreateRequest: Encodable {
    let name: String
    let description: String?
    let trainingTheme: String?
}

struct FitnessTemplateCreateResponse: Decodable {
    let id: Int
    let name: String
}

struct FitnessTemplateUpdateRequest: Encodable {
    let name: String?
    let trainingTheme: String?
    let description: String?
}

struct FitnessTemplateDetail: Decodable {
    let id: Int
    let name: String
    let description: String?
    let trainingTheme: String?
    let exercises: [TemplateDetailExercise]
}

struct TemplateDetailExercise: Decodable, Identifiable {
    let templateExerciseId: Int
    let exerciseId: Int
    let name: String
    let categoryName: String?
    let trackingType: String
    let sortOrder: Int
    let restSeconds: Int?
    let note: String?
    let sets: [TemplateDetailSet]
    var id: Int { templateExerciseId }
}

struct TemplateDetailSet: Decodable, Identifiable {
    let templateSetId: Int
    let setOrder: Int
    let setType: String
    let targetWeightKg: Double?
    let targetReps: Int?
    let targetDurationSeconds: Int?
    let targetDistanceMeters: Double?
    let restSeconds: Int?
    let note: String?
    var id: Int { templateSetId }
}

// MARK: - Save structure

struct SaveTemplateStructureRequest: Encodable {
    let exercises: [SaveExerciseItem]
    let deletedTemplateExerciseIds: [Int]
    let deletedTemplateSetIds: [Int]
}

struct SaveExerciseItem: Encodable {
    let templateExerciseId: Int?
    let exerciseId: Int
    let sortOrder: Int
    let restSeconds: Int
    let note: String
    let sets: [SaveSetItem]
}

struct SaveSetItem: Encodable {
    let templateSetId: Int?
    let setOrder: Int
    let setType: String
    let targetWeightKg: Double?
    let targetReps: Int?
    let targetDurationSeconds: Int?
    let targetDistanceMeters: Double?
    let restSeconds: Int
    let note: String
}

struct SaveTemplateStructureResponse: Decodable {
    let id: Int
    let exerciseCount: Int
    let setCount: Int
}

// MARK: - Exercise models

struct ExerciseCategory: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct ExerciseMuscle: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct MuscleGroup: Decodable, Identifiable {
    let id: Int
    let name: String
    let code: String?
    let parentId: Int?
    let bodyRegion: String?
    let bodyView: String?
}

struct FitnessExercise: Decodable, Identifiable {
    let id: Int
    let name: String
    let category: ExerciseCategory?
    let trackingType: String
    let isTimeBased: Bool
    let supportsDistance: Bool
    let imageUrl: String?
    let primaryMuscles: [ExerciseMuscle]
    let secondaryMuscles: [ExerciseMuscle]
    let isSystem: Bool
}

struct FitnessExercisesPage: Decodable {
    let items: [FitnessExercise]
    let page: Int
    let pageSize: Int
    let total: Int
}

struct ExerciseCreateRequest: Encodable {
    let name: String
    let categoryId: Int?
    let trackingType: String
    let exerciseType: String
    let isTimeBased: Bool
    let supportsDistance: Bool
    let primaryMuscleIds: [Int]
    let secondaryMuscleIds: [Int]
}

struct ExercisePatchRequest: Encodable {
    let name: String?
    let categoryId: Int?
    let trackingType: String?
    let exerciseType: String?
}

struct ExerciseCreateResponse: Decodable {
    let id: Int
    let name: String
    let isSystem: Bool
}

// MARK: - Session models

struct FitnessSessionSummary: Decodable, Identifiable {
    let id: Int
    let name: String
    let trainingTheme: String?
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let totalVolumeKg: Double
    let totalExercises: Int
    let totalSets: Int
    let hasAnalysis: Bool?
}

struct FitnessSessionsPage: Decodable {
    let items: [FitnessSessionSummary]
    let page: Int
    let pageSize: Int
    let total: Int
}

struct FitnessSessionCreateRequest: Encodable {
    let templateId: Int?
    let name: String?
}

struct FitnessSessionCreateResponse: Decodable {
    let sessionId: Int
    let status: String
}

struct FitnessSessionDetail: Decodable, Identifiable {
    let id: Int
    let templateId: Int?
    let trainingTheme: String?
    let name: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let totalVolumeKg: Double
    let totalSets: Int
    let totalReps: Int?
    let totalExercises: Int
    let analysisText: String?
    let exercises: [FitnessSessionExercise]
}

struct FitnessSessionExercise: Decodable, Identifiable {
    let sessionExerciseId: Int
    let exerciseId: Int
    let name: String
    let trackingType: String
    let exerciseType: String
    let imageUrl: String?
    let sortOrder: Int
    let restSeconds: Int
    let note: String?
    let sets: [FitnessSessionSet]

    var id: Int { sessionExerciseId }
    var isTimeBased: Bool { ExerciseTrackingDisplay.isTimeBased(trackingType) }
    var showSecondColumn: Bool { ExerciseTrackingDisplay.showsSecondColumn(trackingType) }
}

struct FitnessSessionSet: Decodable, Identifiable {
    let sessionSetId: Int
    let templateSetId: Int?
    let setOrder: Int
    let setType: String
    let plannedWeightKg: Double?
    let plannedReps: Int?
    let plannedDurationSeconds: Int?
    let plannedDistanceMeters: Double?
    let actualWeightKg: Double?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let timerStatus: String?
    let timerStartedAt: Date?
    let timerAccumulatedSeconds: Int?
    let rpe: Double?
    let isCompleted: Bool
    let completedAt: Date?
    let restSeconds: Int?
    let note: String?

    var id: Int { sessionSetId }
}

struct FitnessSessionCompleteRequest: Encodable {
    let endedAt: String?
    let notes: String?
    let rpe: Double?
}

struct FitnessSessionCompleteResponse: Decodable {
    let sessionId: Int
    let status: String
    let durationSeconds: Int?
    let totalVolumeKg: Double
    let totalSets: Int
    let totalReps: Int?
    let totalExercises: Int
    let analysisGenerated: Bool
}

struct FitnessSessionStructureRequest: Encodable {
    let exercises: [FitnessSessionExerciseRequest]
    let deletedSessionExerciseIds: [Int]
    let deletedSessionSetIds: [Int]
}

struct FitnessSessionExerciseRequest: Encodable {
    let sessionExerciseId: Int?
    let exerciseId: Int
    let sortOrder: Int
    let restSeconds: Int
    let note: String?
    let sets: [FitnessSessionSetRequest]
}

struct FitnessSessionSetRequest: Encodable {
    let sessionSetId: Int?
    let setOrder: Int
    let setType: String
    let plannedWeightKg: Double?
    let plannedReps: Int?
    let plannedDurationSeconds: Int?
    let plannedDistanceMeters: Double?
    let actualWeightKg: Double?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let timerStatus: String?
    let timerStartedAt: String?
    let timerAccumulatedSeconds: Int?
    let rpe: Double?
    let isCompleted: Bool
    let completedAt: String?
    let restSeconds: Int?
    let note: String?
}

struct FitnessSessionStructureResponse: Decodable {
    let sessionId: Int
    let totalVolumeKg: Double
    let totalSets: Int
    let totalReps: Int?
    let updatedAt: Date?
}

struct FitnessSessionAnalysisResponse: Decodable {
    let sessionId: Int
    let trainingTheme: String?
    let generatedAt: String?
    let analysisText: String?
    let analysisJson: String?
}

struct FitnessSessionSummaryInfo: Decodable {
    let id: Int
    let name: String
    let trainingTheme: String?
    let status: String
    let startedAt: String?
    let endedAt: String?
    let durationSeconds: Int?
    let totalVolumeKg: Double?
    let totalSets: Int?
    let totalReps: Int?
    let totalExercises: Int?
    let activeEnergyKcal: Double?
    let totalEnergyKcal: Double?
}

struct FitnessSessionSummaryExerciseItem: Decodable, Identifiable {
    let sessionExerciseId: Int
    let exerciseId: Int
    let name: String
    let trackingType: String
    let exerciseType: String?
    let imageUrl: String?
    let sortOrder: Int
    let completedSets: Int
    let totalVolumeKg: Double?
    let totalDistanceMeters: Double?
    let totalDurationSeconds: Int?
    var id: Int { sessionExerciseId }
}

struct FitnessSessionSummaryAnalysis: Decodable {
    let analysisText: String?
    let analysisJson: String?
    let generatedAt: String?
}

struct FitnessSessionSummaryResponse: Decodable {
    let session: FitnessSessionSummaryInfo
    let activeEnergyKcal: Double?
    let totalEnergyKcal: Double?
    let exercises: [FitnessSessionSummaryExerciseItem]
    let muscles: [FitnessStrengthVolumeMuscle]
    let analysis: FitnessSessionSummaryAnalysis?
}

struct FitnessTrainingSplit: Decodable {
    let strengthPercent: Double
    let cardioPercent: Double
}

struct FitnessBreakdownMuscleItem: Decodable, Identifiable {
    let muscleCode: String
    let muscleName: String
    let percent: Double
    var id: String { muscleCode }
}

struct FitnessBreakdownSetItem: Decodable, Identifiable {
    let sessionSetId: Int
    let setOrder: Int
    let setType: String
    let actualWeightKg: Double?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let restSeconds: Int?
    let isCompleted: Bool
    let completedAt: String?
    var id: Int { sessionSetId }
}

struct FitnessBreakdownExerciseItem: Decodable, Identifiable {
    let sessionExerciseId: Int
    let exerciseId: Int
    let exerciseName: String
    let exerciseType: String?
    let trackingType: String
    let setCount: Int
    let sets: [FitnessBreakdownSetItem]
    var id: Int { sessionExerciseId }
}

struct FitnessSessionBreakdownResponse: Decodable {
    let session: FitnessSessionSummaryInfo
    let trainingSplit: FitnessTrainingSplit
    let muscleLoadDistribution: [FitnessBreakdownMuscleItem]
    let exercises: [FitnessBreakdownExerciseItem]
}

struct FitnessHeartRateSummary: Decodable {
    let avgBpm: Int?
    let minBpm: Int?
    let maxBpm: Int?
    let currentZone: Int?
}

struct FitnessHeartRateZoneStat: Decodable, Identifiable {
    let zone: Int
    let durationSeconds: Int
    let percent: Double
    var id: Int { zone }
}

struct FitnessHeartRatePoint: Decodable, Identifiable {
    let time: String
    let bpm: Int?
    let zone: Int?
    var id: String { time }
}

struct FitnessHeartRateRecovery: Decodable {
    let available: Bool
    let hrDropBpm: Int?
}

struct FitnessSessionHeartRateResponse: Decodable {
    let session: FitnessSessionSummaryInfo
    let summary: FitnessHeartRateSummary
    let zoneStats: [FitnessHeartRateZoneStat]
    let timeSeries: [FitnessHeartRatePoint]
    let recovery: FitnessHeartRateRecovery
}

struct FitnessExerciseHistory: Identifiable {
    let exerciseId: Int
    let exerciseName: String
    let trackingType: String
    let entries: [FitnessExerciseHistoryEntry]

    var id: Int { exerciseId }
}

struct FitnessExerciseHistoryEntry: Identifiable {
    let sessionId: Int
    let date: Date
    let sets: [FitnessExerciseHistorySet]

    var id: Int { sessionId }
}

struct FitnessExerciseHistorySet: Identifiable {
    let id: Int
    let setOrder: Int
    let weightKg: Double?
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
}

// MARK: - Exercise Progress models

struct ExerciseProgressDisplayConfig: Decodable {
    let preferredMetric: String
    let metricKind: String
    let usesWeight: Bool
    let usesReps: Bool
    let usesDuration: Bool
    let usesDistance: Bool
}

struct ExerciseProgressPoint: Decodable, Identifiable {
    let date: String
    let value: Double
    var id: String { date }
}

struct ExerciseHistorySetItem: Decodable, Identifiable {
    let setOrder: Int
    let setType: String
    let actualWeightKg: Double?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let isCompleted: Bool
    let completedAt: String?
    let estimated1Rm: Double?
    let volumeKg: Double?
    var id: Int { setOrder }
}

struct ExerciseHistorySessionItem: Decodable, Identifiable {
    let sessionId: Int
    let sessionName: String
    let trainingTheme: String?
    let startedAt: String?
    let endedAt: String?
    let sessionStatus: String
    let metricValue: Double?
    let bestWeightKg: Double?
    let bestReps: Int?
    let totalVolumeKg: Double?
    let totalDistanceMeters: Double?
    let totalDurationSeconds: Int?
    let bestDistanceMeters: Double?
    let bestDurationSeconds: Int?
    let completedSets: Int
    let sets: [ExerciseHistorySetItem]
    var id: Int { sessionId }
}

struct ExerciseProgressSummaryData: Decodable {
    let sessionCount: Int
    let completedSetCount: Int
    let latestMetricValue: Double?
    let previousMetricValue: Double?
    let changePercent: Double?
    let bestMetricValue: Double?
    let bestWeightKg: Double?
    let bestReps: Int?
    let totalVolumeKg: Double?
    let totalDistanceMeters: Double?
    let totalDurationSeconds: Int?
    let bestDistanceMeters: Double?
    let bestDurationSeconds: Int?
}

struct ExerciseProgressResponse: Decodable {
    let exerciseId: Int
    let exerciseName: String
    let metric: String
    let display: ExerciseProgressDisplayConfig
    let summary: ExerciseProgressSummaryData
    let items: [ExerciseProgressPoint]
    let history: [ExerciseHistorySessionItem]
}
