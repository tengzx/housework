import SwiftUI
import Combine

/// Drives one active workout session on the watch, talking to the same REST API
/// the iPhone app uses (`FitnessAPIClient`) so every action — starting a set,
/// logging real reps/weight, finishing — is reflected in the app immediately.
@MainActor
final class WatchWorkoutViewModel: ObservableObject {
    let sessionId: Int
    let sessionName: String

    @Published private(set) var detail: FitnessSessionDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var busySetIds: Set<Int> = []
    @Published private(set) var isCompleting = false
    @Published var errorMessage: String?

    private var needsReloadAfterCurrentLoad = false
    private var pendingOperations: [FitnessSessionOperationRequest] = []
    private var isFlushingOperations = false

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(sessionId: Int, name: String) {
        self.sessionId = sessionId
        self.sessionName = name
        self.pendingOperations = Self.loadPendingOperations(sessionId: sessionId)
        Task { await flushPendingOperations() }
    }

    // MARK: - Derived state

    struct SetContext: Identifiable {
        let index: Int
        let exerciseSetIndex: Int
        let exerciseSetCount: Int
        let exercise: FitnessSessionExercise
        let set: FitnessSessionSet
        var id: Int { self.set.sessionSetId }
    }

    /// All sets across all exercises, in workout order.
    var orderedContexts: [SetContext] {
        guard let detail else { return [] }
        var out: [SetContext] = []
        for exercise in detail.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let sets = exercise.sets.sorted(by: { $0.setOrder < $1.setOrder })
            for (setIndex, set) in sets.enumerated() {
                out.append(SetContext(
                    index: out.count,
                    exerciseSetIndex: setIndex,
                    exerciseSetCount: sets.count,
                    exercise: exercise,
                    set: set
                ))
            }
        }
        return out
    }

    var totalCount: Int { orderedContexts.count }
    var completedCount: Int { orderedContexts.filter { $0.set.isCompleted }.count }
    var isFinished: Bool {
        let c = orderedContexts
        return !c.isEmpty && c.allSatisfy { $0.set.isCompleted }
    }
    var canUpdateTemplate: Bool { detail?.templateId != nil }

    func isBusy(_ setId: Int) -> Bool { busySetIds.contains(setId) }

    /// The set the session should advance to next: keep finishing the current
    /// exercise, then fall back to the first still-available set.
    var nextTarget: SetContext? {
        let contexts = orderedContexts
        func available(_ c: SetContext) -> Bool { !c.set.isCompleted && c.set.timerStatus != "running" }
        let lastCompleted = contexts
            .filter { $0.set.isCompleted }
            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
        if let lastCompleted,
           let sameExercise = contexts.first(where: {
               $0.exercise.sessionExerciseId == lastCompleted.exercise.sessionExerciseId && available($0)
           }) {
            return sameExercise
        }
        return contexts.first(where: available)
    }

    var runningContext: SetContext? {
        orderedContexts.first { $0.set.timerStatus == "running" }
    }

    var lastCompleted: SetContext? {
        orderedContexts
            .filter { $0.set.isCompleted }
            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
    }

    /// Seconds of rest remaining before `context` (the next set) should begin,
    /// based on the last completed set's rest interval. `nil` if not resting.
    func restRemaining(for context: SetContext, now: Date) -> Int? {
        guard nextTarget?.id == context.id else { return nil }
        guard let last = lastCompleted, let completedAt = last.set.completedAt else { return nil }
        let rest = last.set.restSeconds ?? last.exercise.restSeconds
        let remaining = rest - Int(now.timeIntervalSince(completedAt))
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Loading

    func load() async {
        if isLoading {
            needsReloadAfterCurrentLoad = true
            return
        }

        repeat {
            needsReloadAfterCurrentLoad = false
            isLoading = true
            errorMessage = nil
            do {
                detail = try await fetchDetail()
            } catch {
                errorMessage = SharedL10n.tr("watch.fitness.load_failed")
            }
            isLoading = false
        } while needsReloadAfterCurrentLoad
    }

    // MARK: - Set actions

    /// Start a set's timer (idle → running). Any set already running is idled first.
    func startSet(_ setId: Int) async {
        guard !busySetIds.contains(setId) else { return }
        if await refreshShowsSetCompleted(setId) { return }
        if let context = orderedContexts.first(where: { $0.id == setId }) {
            WorkoutSessionRecorder.shared.logSetStart(
                setId: setId,
                exercise: context.exercise.name,
                setIndex: context.exerciseSetIndex
            )
        }
        let operation = makeOperation(type: "start_set", setId: setId)
        applyOptimistic(operation)
        broadcastCurrentSnapshot()
        enqueueOperation(operation)
    }

    /// Mark a set complete and record the real reps/weight (or duration/distance).
    func completeSet(
        setId: Int,
        actualWeightKg: Double?,
        actualReps: Int?,
        actualDurationSeconds: Int?,
        actualDistanceMeters: Double?
    ) async {
        guard !busySetIds.contains(setId) else { return }
        WorkoutSessionRecorder.shared.logSetComplete(setId: setId, reps: actualReps, weightKg: actualWeightKg)
        if await refreshShowsSetCompleted(setId) { return }
        let operation = makeOperation(
            type: "complete_set",
            setId: setId,
            actualWeightKg: actualWeightKg,
            actualReps: actualReps,
            actualDurationSeconds: actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters
        )
        applyOptimistic(operation)
        broadcastCurrentSnapshot()
        enqueueOperation(operation)
    }

    /// Re-open a completed set (uncheck it) so the user can redo it.
    func reopenSet(_ setId: Int) async {
        guard !busySetIds.contains(setId) else { return }
        let operation = makeOperation(type: "reopen_set", setId: setId)
        applyOptimistic(operation)
        broadcastCurrentSnapshot()
        enqueueOperation(operation)
    }

    func deleteSet(_ setId: Int) async {
        await waitForPendingLoad()
        errorMessage = nil
        do {
            let latest = try await fetchDetail()
            detail = latest
            let exercises = latest.exercises.map { exercise -> FitnessSessionExerciseRequest in
                let sets = exercise.sets
                    .filter { $0.sessionSetId != setId }
                    .sorted { $0.setOrder < $1.setOrder }
                    .enumerated()
                    .map { idx, set -> FitnessSessionSetRequest in
                        let req = setRequest(from: set, exercise: exercise)
                        return FitnessSessionSetRequest(
                            sessionSetId: req.sessionSetId,
                            setOrder: idx + 1,
                            setType: req.setType,
                            plannedWeightKg: req.plannedWeightKg,
                            plannedReps: req.plannedReps,
                            plannedDurationSeconds: req.plannedDurationSeconds,
                            plannedDistanceMeters: req.plannedDistanceMeters,
                            actualWeightKg: req.actualWeightKg,
                            actualReps: req.actualReps,
                            actualDurationSeconds: req.actualDurationSeconds,
                            actualDistanceMeters: req.actualDistanceMeters,
                            timerStatus: req.timerStatus,
                            timerStartedAt: req.timerStartedAt,
                            timerAccumulatedSeconds: req.timerAccumulatedSeconds,
                            rpe: req.rpe,
                            isCompleted: req.isCompleted,
                            completedAt: req.completedAt,
                            restSeconds: req.restSeconds,
                            note: req.note
                        )
                    }
                return FitnessSessionExerciseRequest(
                    sessionExerciseId: exercise.sessionExerciseId,
                    exerciseId: exercise.exerciseId,
                    sortOrder: exercise.sortOrder,
                    restSeconds: exercise.restSeconds,
                    note: exercise.note,
                    sets: sets
                )
            }
            let request = FitnessSessionStructureRequest(
                exercises: exercises,
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: [setId]
            )
            detail = try await saveStructure(request)
        } catch {
            errorMessage = SharedL10n.tr("watch.fitness.delete_failed")
        }
    }

    // MARK: - Completion

    func discard() async -> Bool {
        errorMessage = nil
        do {
            try await discardSession()
            return true
        } catch {
            errorMessage = SharedL10n.tr("watch.fitness.delete_failed")
            return false
        }
    }

    func complete(rpe: Double?) async -> Bool {
        guard !isCompleting else { return false }
        isCompleting = true
        errorMessage = nil
        defer { isCompleting = false }
        do {
            try await completeSession(rpe: rpe)
            return true
        } catch {
            errorMessage = SharedL10n.tr("watch.fitness.complete_failed")
            return false
        }
    }

    // MARK: - Structure request helpers

    private func waitForPendingLoad() async {
        while isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func makeOperation(
        type: String,
        setId: Int,
        actualWeightKg: Double? = nil,
        actualReps: Int? = nil,
        actualDurationSeconds: Int? = nil,
        actualDistanceMeters: Double? = nil,
        rpe: Double? = nil,
        now: Date = .now
    ) -> FitnessSessionOperationRequest {
        FitnessSessionOperationRequest(
            operationId: UUID().uuidString,
            type: type,
            sessionSetId: setId,
            actualWeightKg: actualWeightKg,
            actualReps: actualReps,
            actualDurationSeconds: actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters,
            rpe: rpe,
            clientTime: Self.iso.string(from: now)
        )
    }

    private func enqueueOperation(_ operation: FitnessSessionOperationRequest) {
        pendingOperations.append(operation)
        persistPendingOperations()
        Task { await flushPendingOperations() }
    }

    private func flushPendingOperations() async {
        guard !isFlushingOperations else { return }
        isFlushingOperations = true
        defer { isFlushingOperations = false }
        while !pendingOperations.isEmpty {
            let operation = pendingOperations[0]
            do {
                let fresh = try await applyOperation(operation)
                pendingOperations.removeFirst()
                persistPendingOperations()
                detail = fresh
                WatchAuthSync.shared.broadcastSessionSnapshot(fresh)
                errorMessage = nil
            } catch {
                errorMessage = SharedL10n.tr("watch.fitness.syncing")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if pendingOperations.first?.operationId == operation.operationId {
                    Task { await flushPendingOperations() }
                    return
                }
            }
        }
    }

    private func persistPendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            UserDefaults.standard.set(data, forKey: Self.pendingOperationsKey(sessionId: sessionId))
        }
    }

    private static func loadPendingOperations(sessionId: Int) -> [FitnessSessionOperationRequest] {
        guard let data = UserDefaults.standard.data(forKey: pendingOperationsKey(sessionId: sessionId)),
              let operations = try? JSONDecoder().decode([FitnessSessionOperationRequest].self, from: data) else {
            return []
        }
        return operations
    }

    private static func pendingOperationsKey(sessionId: Int) -> String {
        "watch.fitness.pendingOperations.\(sessionId)"
    }

    private func applyOperation(_ operation: FitnessSessionOperationRequest) async throws -> FitnessSessionDetail {
        do {
            return try await WatchAuthSync.shared.phoneApplySessionOperation(id: sessionId, request: operation)
        } catch {
            let fresh = try await FitnessAPIClient.applySessionOperation(id: sessionId, request: operation)
            WatchAuthSync.shared.broadcastSessionChanged(sessionId)
            return fresh
        }
    }

    private func applyOptimistic(_ operation: FitnessSessionOperationRequest) {
        guard let detail else { return }
        let now = Self.iso.date(from: operation.clientTime) ?? .now
        let exercises = detail.exercises.map { exercise in
            let sets = exercise.sets.map { set in
                optimisticSet(set, exercise: exercise, operation: operation, now: now)
            }
            return exercise.replacingSets(sets)
        }
        self.detail = detail.replacingExercises(exercises)
    }

    func applyRemoteSnapshot(_ snapshot: FitnessSessionDetail) {
        guard snapshot.id == sessionId else { return }
        detail = snapshot
    }

    private func broadcastCurrentSnapshot() {
        guard let detail else { return }
        WatchAuthSync.shared.broadcastSessionSnapshot(detail)
    }

    private func refreshShowsSetCompleted(_ setId: Int) async -> Bool {
        do {
            let latest = try await fetchDetail()
            detail = latest
            return latest.exercises.flatMap(\.sets).first { $0.sessionSetId == setId }?.isCompleted == true
        } catch {
            return false
        }
    }

    private func optimisticSet(
        _ set: FitnessSessionSet,
        exercise: FitnessSessionExercise,
        operation: FitnessSessionOperationRequest,
        now: Date
    ) -> FitnessSessionSet {
        let isTarget = set.sessionSetId == operation.sessionSetId
        if operation.type == "start_set" {
            if isTarget {
                return set.replacing(timerStatus: "running", timerStartedAt: now, timerAccumulatedSeconds: set.timerAccumulatedSeconds ?? 0, isCompleted: false, clearCompletedAt: true)
            }
            if set.timerStatus == "running" {
                let elapsed = set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
                return set.replacing(timerStatus: "idle", clearTimerStartedAt: true, timerAccumulatedSeconds: (set.timerAccumulatedSeconds ?? 0) + elapsed)
            }
            return set
        }
        guard isTarget else { return set }
        switch operation.type {
        case "complete_set":
            let elapsed = set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            let accumulated = (set.timerAccumulatedSeconds ?? 0) + (set.timerStatus == "running" ? elapsed : 0)
            return set.replacing(
                actualWeightKg: operation.actualWeightKg ?? set.plannedWeightKg,
                actualReps: operation.actualReps ?? set.plannedReps,
                actualDurationSeconds: operation.actualDurationSeconds ?? (exercise.isTimeBased ? accumulated : set.plannedDurationSeconds),
                actualDistanceMeters: operation.actualDistanceMeters ?? set.plannedDistanceMeters,
                timerStatus: "idle",
                clearTimerStartedAt: true,
                timerAccumulatedSeconds: accumulated,
                rpe: operation.rpe ?? set.rpe,
                isCompleted: true,
                completedAt: now
            )
        case "reopen_set":
            return set.replacing(timerStatus: "idle", clearTimerStartedAt: true, isCompleted: false, clearCompletedAt: true)
        default:
            return set
        }
    }

    private func fetchDetail() async throws -> FitnessSessionDetail {
        do {
            return try await WatchAuthSync.shared.phoneSessionDetail(id: sessionId)
        } catch {
            return try await FitnessAPIClient.sessionDetail(id: sessionId)
        }
    }

    private func saveStructure(_ request: FitnessSessionStructureRequest) async throws -> FitnessSessionDetail {
        do {
            return try await WatchAuthSync.shared.phoneSaveSessionStructure(id: sessionId, request: request)
        } catch {
            _ = try await FitnessAPIClient.saveSessionStructure(id: sessionId, request: request)
            WatchAuthSync.shared.broadcastSessionChanged(sessionId)
            return try await FitnessAPIClient.sessionDetail(id: sessionId)
        }
    }

    private func completeSession(rpe: Double?) async throws {
        do {
            try await WatchAuthSync.shared.phoneCompleteSession(id: sessionId, rpe: rpe)
        } catch {
            _ = try await FitnessAPIClient.completeSession(id: sessionId, rpe: rpe)
        }
    }

    private func discardSession() async throws {
        do {
            try await WatchAuthSync.shared.phoneDiscardSession(id: sessionId)
        } catch {
            try await FitnessAPIClient.discardSession(id: sessionId)
        }
    }

    private func structureRequest(
        from detail: FitnessSessionDetail,
        mapper: (FitnessSessionExercise, FitnessSessionSet) -> FitnessSessionSetRequest
    ) -> FitnessSessionStructureRequest {
        let exercises = detail.exercises.map { exercise in
            FitnessSessionExerciseRequest(
                sessionExerciseId: exercise.sessionExerciseId,
                exerciseId: exercise.exerciseId,
                sortOrder: exercise.sortOrder,
                restSeconds: exercise.restSeconds,
                note: exercise.note,
                sets: exercise.sets.map { mapper(exercise, $0) }
            )
        }
        return FitnessSessionStructureRequest(
            exercises: exercises,
            deletedSessionExerciseIds: [],
            deletedSessionSetIds: []
        )
    }

    private func setRequest(
        from set: FitnessSessionSet,
        exercise: FitnessSessionExercise,
        isCompleted: Bool? = nil,
        clearCompletedAt: Bool = false,
        timerStatus: String? = nil,
        timerStartedAt: String? = nil,
        clearTimerStartedAt: Bool = false,
        timerAccumulatedSeconds: Int? = nil
    ) -> FitnessSessionSetRequest {
        let completed = isCompleted ?? set.isCompleted
        let completedAt = clearCompletedAt
            ? nil
            : (completed ? (set.completedAt.map { Self.iso.string(from: $0) } ?? Self.iso.string(from: .now)) : nil)
        let startedAt = clearTimerStartedAt
            ? nil
            : (timerStartedAt ?? set.timerStartedAt.map { Self.iso.string(from: $0) })
        return FitnessSessionSetRequest(
            sessionSetId: set.sessionSetId,
            setOrder: set.setOrder,
            setType: set.setType,
            plannedWeightKg: set.plannedWeightKg,
            plannedReps: set.plannedReps,
            plannedDurationSeconds: set.plannedDurationSeconds,
            plannedDistanceMeters: set.plannedDistanceMeters,
            actualWeightKg: set.actualWeightKg,
            actualReps: set.actualReps,
            actualDurationSeconds: set.actualDurationSeconds,
            actualDistanceMeters: set.actualDistanceMeters,
            timerStatus: timerStatus ?? set.timerStatus ?? "idle",
            timerStartedAt: startedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds ?? set.timerAccumulatedSeconds ?? 0,
            rpe: set.rpe,
            isCompleted: completed,
            completedAt: completedAt,
            restSeconds: set.restSeconds ?? exercise.restSeconds,
            note: set.note
        )
    }
}

private extension FitnessSessionExercise {
    func replacingSets(_ sets: [FitnessSessionSet]) -> FitnessSessionExercise {
        FitnessSessionExercise(
            sessionExerciseId: sessionExerciseId,
            exerciseId: exerciseId,
            name: name,
            trackingType: trackingType,
            exerciseType: exerciseType,
            imageUrl: imageUrl,
            sortOrder: sortOrder,
            restSeconds: restSeconds,
            note: note,
            sets: sets
        )
    }
}

private extension FitnessSessionDetail {
    func replacingExercises(_ exercises: [FitnessSessionExercise]) -> FitnessSessionDetail {
        FitnessSessionDetail(
            id: id,
            templateId: templateId,
            trainingTheme: trainingTheme,
            name: name,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalVolumeKg: totalVolumeKg,
            totalSets: totalSets,
            totalReps: totalReps,
            totalExercises: totalExercises,
            analysisText: analysisText,
            exercises: exercises
        )
    }
}

private extension FitnessSessionSet {
    func replacing(
        actualWeightKg: Double? = nil,
        actualReps: Int? = nil,
        actualDurationSeconds: Int? = nil,
        actualDistanceMeters: Double? = nil,
        timerStatus: String? = nil,
        timerStartedAt: Date? = nil,
        clearTimerStartedAt: Bool = false,
        timerAccumulatedSeconds: Int? = nil,
        rpe: Double? = nil,
        isCompleted: Bool? = nil,
        completedAt: Date? = nil,
        clearCompletedAt: Bool = false
    ) -> FitnessSessionSet {
        FitnessSessionSet(
            sessionSetId: sessionSetId,
            templateSetId: templateSetId,
            setOrder: setOrder,
            setType: setType,
            plannedWeightKg: plannedWeightKg,
            plannedReps: plannedReps,
            plannedDurationSeconds: plannedDurationSeconds,
            plannedDistanceMeters: plannedDistanceMeters,
            actualWeightKg: actualWeightKg ?? self.actualWeightKg,
            actualReps: actualReps ?? self.actualReps,
            actualDurationSeconds: actualDurationSeconds ?? self.actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters ?? self.actualDistanceMeters,
            timerStatus: timerStatus ?? self.timerStatus,
            timerStartedAt: clearTimerStartedAt ? nil : (timerStartedAt ?? self.timerStartedAt),
            timerAccumulatedSeconds: timerAccumulatedSeconds ?? self.timerAccumulatedSeconds,
            rpe: rpe ?? self.rpe,
            isCompleted: isCompleted ?? self.isCompleted,
            completedAt: clearCompletedAt ? nil : (completedAt ?? self.completedAt),
            restSeconds: restSeconds,
            note: note
        )
    }
}
