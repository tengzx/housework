import Foundation

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
