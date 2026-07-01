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

// MARK: - Envelope

private struct FitnessEnvelope<T: Decodable>: Decodable {
    let code: Int
    let data: T
}

private struct FitnessNullData: Decodable {}

// MARK: - Client

enum FitnessAPIClient {
    static let baseURL = URL(string: "http://100.67.64.11:8081/api/v1")!
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let fractionalIsoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Templates
    static func templates() async throws -> [FitnessTemplateSummary] {
        try await get([FitnessTemplateSummary].self, path: "workout-templates")
    }

    @discardableResult
    static func createTemplate(name: String, description: String?, trainingTheme: String?) async throws -> FitnessTemplateCreateResponse {
        let body = FitnessTemplateCreateRequest(name: name, description: description, trainingTheme: trainingTheme)
        return try await post(FitnessTemplateCreateResponse.self, path: "workout-templates", body: body)
    }

    static func templateDetail(id: Int) async throws -> FitnessTemplateDetail {
        try await get(FitnessTemplateDetail.self, path: "workout-templates/\(id)")
    }

    static func saveTemplateStructure(id: Int, request: SaveTemplateStructureRequest) async throws -> SaveTemplateStructureResponse {
        let url = baseURL.appendingPathComponent("workout-templates/\(id)/structure")
        let envelope = try await send(FitnessEnvelope<SaveTemplateStructureResponse>.self, url: url, method: "PUT", body: request)
        return envelope.data
    }

    @discardableResult
    static func updateTemplate(id: Int, name: String?, trainingTheme: String?, description: String?) async throws -> FitnessTemplateCreateResponse {
        let body = FitnessTemplateUpdateRequest(name: name, trainingTheme: trainingTheme, description: description)
        let url = baseURL.appendingPathComponent("workout-templates/\(id)")
        let envelope = try await send(FitnessEnvelope<FitnessTemplateCreateResponse>.self, url: url, method: "PATCH", body: body)
        return envelope.data
    }

    static func deleteTemplate(id: Int) async throws {
        let url = baseURL.appendingPathComponent("workout-templates/\(id)")
        _ = try await send(FitnessEnvelope<FitnessNullData>.self, url: url, method: "DELETE", body: Optional<String>.none)
    }

    // Exercises
    static func exercises(keyword: String? = nil, categoryId: Int? = nil, muscleGroupId: Int? = nil, page: Int = 1, pageSize: Int = 100) async throws -> FitnessExercisesPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("exercises"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let kw = keyword, !kw.isEmpty { items.append(URLQueryItem(name: "keyword", value: kw)) }
        if let cid = categoryId { items.append(URLQueryItem(name: "categoryId", value: "\(cid)")) }
        if let mid = muscleGroupId { items.append(URLQueryItem(name: "muscleGroupId", value: "\(mid)")) }
        components.queryItems = items
        let envelope = try await send(FitnessEnvelope<FitnessExercisesPage>.self, url: components.url!, method: "GET", body: Optional<String>.none)
        return envelope.data
    }

    static func exerciseCategories() async throws -> [ExerciseCategory] {
        try await get([ExerciseCategory].self, path: "exercise-categories")
    }

    static func muscleGroups() async throws -> [MuscleGroup] {
        try await get([MuscleGroup].self, path: "muscle-groups")
    }

    @discardableResult
    static func createExercise(name: String, categoryId: Int?, trackingType: String) async throws -> ExerciseCreateResponse {
        let body = ExerciseCreateRequest(
            name: name,
            categoryId: categoryId,
            trackingType: trackingType,
            exerciseType: "strength",
            isTimeBased: ExerciseTrackingDisplay.isTimeBased(trackingType),
            supportsDistance: ExerciseTrackingDisplay.isDistanceBased(trackingType),
            primaryMuscleIds: [],
            secondaryMuscleIds: []
        )
        return try await post(ExerciseCreateResponse.self, path: "exercises", body: body)
    }

    @discardableResult
    static func updateExercise(id: Int, name: String?, categoryId: Int?, trackingType: String?) async throws -> ExerciseCreateResponse {
        let body = ExercisePatchRequest(name: name, categoryId: categoryId, trackingType: trackingType, exerciseType: nil)
        let url = baseURL.appendingPathComponent("exercises/\(id)")
        let envelope = try await send(FitnessEnvelope<ExerciseCreateResponse>.self, url: url, method: "PATCH", body: body)
        return envelope.data
    }

    static func deleteExercise(id: Int) async throws {
        let url = baseURL.appendingPathComponent("exercises/\(id)")
        _ = try await send(FitnessEnvelope<FitnessNullData>.self, url: url, method: "DELETE", body: Optional<String>.none)
    }

    // Dashboard / sessions
    static func dashboard() async throws -> FitnessDashboardResponse {
        try await get(FitnessDashboardResponse.self, path: "dashboard")
    }

    static func recentSessions(pageSize: Int = 5) async throws -> [FitnessSessionSummary] {
        var components = URLComponents(url: baseURL.appendingPathComponent("workout-sessions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "status", value: "completed"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        let envelope = try await send(FitnessEnvelope<FitnessSessionsPage>.self, url: components.url!, method: "GET", body: Optional<String>.none)
        return envelope.data.items
    }

    static func exerciseHistory(exerciseId: Int, pageSize: Int = 20) async throws -> FitnessExerciseHistory {
        let sessions = try await recentSessions(pageSize: pageSize)
        var entries: [FitnessExerciseHistoryEntry] = []
        var exerciseName = ""
        var trackingType = ""

        for session in sessions {
            let detail = try await sessionDetail(id: session.id)
            guard let exercise = detail.exercises.first(where: { $0.exerciseId == exerciseId }) else { continue }
            exerciseName = exerciseName.isEmpty ? exercise.name : exerciseName
            trackingType = trackingType.isEmpty ? exercise.trackingType : trackingType

            let completedSets = exercise.sets.filter { $0.isCompleted }
            let sourceSets = completedSets.isEmpty ? exercise.sets : completedSets
            let historySets = sourceSets.map { set in
                FitnessExerciseHistorySet(
                    id: set.sessionSetId,
                    setOrder: set.setOrder,
                    weightKg: set.actualWeightKg ?? set.plannedWeightKg,
                    reps: set.actualReps ?? set.plannedReps,
                    durationSeconds: set.actualDurationSeconds ?? set.plannedDurationSeconds,
                    distanceMeters: set.actualDistanceMeters ?? set.plannedDistanceMeters
                )
            }

            guard !historySets.isEmpty else { continue }
            entries.append(
                FitnessExerciseHistoryEntry(
                    sessionId: session.id,
                    date: session.endedAt ?? session.startedAt,
                    sets: historySets
                )
            )
        }

        return FitnessExerciseHistory(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            trackingType: trackingType,
            entries: entries.sorted { $0.date > $1.date }
        )
    }

    @discardableResult
    static func startSession(templateId: Int?, name: String?) async throws -> FitnessSessionCreateResponse {
        let body = FitnessSessionCreateRequest(templateId: templateId, name: name)
        return try await post(FitnessSessionCreateResponse.self, path: "workout-sessions", body: body)
    }

    static func sessionDetail(id: Int) async throws -> FitnessSessionDetail {
        try await get(FitnessSessionDetail.self, path: "workout-sessions/\(id)")
    }

    @discardableResult
    static func completeSession(id: Int, notes: String? = nil, rpe: Double? = nil) async throws -> FitnessSessionCompleteResponse {
        let body = FitnessSessionCompleteRequest(endedAt: nil, notes: notes, rpe: rpe)
        return try await post(FitnessSessionCompleteResponse.self, path: "workout-sessions/\(id)/complete", body: body)
    }

    static func discardSession(id: Int) async throws {
        let url = baseURL.appendingPathComponent("workout-sessions/\(id)/discard")
        _ = try await send(FitnessEnvelope<FitnessNullData?>.self, url: url, method: "POST", body: Optional<String>.none)
    }

    @discardableResult
    static func saveSessionStructure(id: Int, request: FitnessSessionStructureRequest) async throws -> FitnessSessionStructureResponse {
        let url = baseURL.appendingPathComponent("workout-sessions/\(id)/structure")
        let envelope = try await send(FitnessEnvelope<FitnessSessionStructureResponse>.self, url: url, method: "PUT", body: request)
        return envelope.data
    }

    static func exerciseProgress(exerciseId: Int, range: String = "30d", metric: String? = nil) async throws -> ExerciseProgressResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("exercises/\(exerciseId)/progress"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "range", value: range)]
        if let metric { queryItems.append(URLQueryItem(name: "metric", value: metric)) }
        components.queryItems = queryItems
        let envelope = try await send(FitnessEnvelope<ExerciseProgressResponse>.self, url: components.url!, method: "GET", body: Optional<String>.none)
        return envelope.data
    }

    // MARK: Internals

    private static func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let envelope = try await send(FitnessEnvelope<T>.self, url: url, method: "GET", body: Optional<String>.none)
        return envelope.data
    }

    private static func post<T: Decodable, Body: Encodable>(_ type: T.Type, path: String, body: Body) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let envelope = try await send(FitnessEnvelope<T>.self, url: url, method: "POST", body: body)
        return envelope.data
    }

    private static func send<T: Decodable, Body: Encodable>(_ type: T.Type, url: URL, method: String, body: Body?) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = fractionalIsoDateFormatter.date(from: rawValue) ?? isoDateFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(rawValue)"
            )
        }
        return try decoder.decode(T.self, from: data)
    }
}
