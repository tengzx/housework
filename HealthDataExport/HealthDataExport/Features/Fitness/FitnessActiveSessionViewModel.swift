import SwiftUI
import Combine
import UIKit
import AudioToolbox


// MARK: - Active Session View

/// Picks the set the workout should advance to next.
///
/// While the exercise of the most-recently-completed set still has an available
/// set, keep advancing within that same exercise (finish the current exercise
/// before moving on). Only once that exercise is fully done do we fall back to
/// the first available set overall — which surfaces any earlier exercise the
/// user skipped over.
func fitnessNextTargetContext(
    in contexts: [(exercise: FitnessSessionExercise, set: FitnessSessionSet)]
) -> (exercise: FitnessSessionExercise, set: FitnessSessionSet)? {
    func isAvailable(_ context: (exercise: FitnessSessionExercise, set: FitnessSessionSet)) -> Bool {
        !context.set.isCompleted && context.set.timerStatus != "running"
    }
    let lastCompleted = contexts
        .filter { $0.set.isCompleted }
        .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
    if let lastCompleted,
       let sameExerciseNext = contexts.first(where: {
           $0.exercise.sessionExerciseId == lastCompleted.exercise.sessionExerciseId && isAvailable($0)
       }) {
        return sameExerciseNext
    }
    return contexts.first(where: isAvailable)
}

struct FitnessWorkoutSessionPayload: Hashable, Identifiable {
    let sessionId: Int
    let name: String

    var id: Int { sessionId }
}

@MainActor
final class FitnessActiveSessionViewModel: ObservableObject {
    let payload: FitnessWorkoutSessionPayload
    @Published private(set) var detail: FitnessSessionDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isCompleting = false
    @Published private(set) var isPausing = false
    @Published private(set) var isDiscarding = false
    @Published private(set) var isAddingExercise = false
    @Published private(set) var isSessionPaused = false
    @Published private(set) var savingSetIds: Set<Int> = []
    @Published private(set) var updatingSetIds: Set<Int> = []
    @Published private(set) var savingExerciseIds: Set<Int> = []
    @Published var errorMessage: String?

    private var sessionPausedAt: Date?
    private var accumulatedSessionPauseSeconds = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(payload: FitnessWorkoutSessionPayload) {
        self.payload = payload
    }

    var title: String { detail?.name ?? payload.name }
    var startedAt: Date { detail?.startedAt ?? .now }
    var hasRunningSet: Bool {
        guard let detail else { return false }
        return orderedSetContexts(from: detail).contains { $0.set.timerStatus == "running" }
    }

    var shouldShowSessionControls: Bool {
        !hasRunningSet
    }

    var incompleteSetCount: Int {
        guard let exercises = detail?.exercises else { return 0 }
        return exercises.reduce(0) { total, ex in
            total + ex.sets.filter { !$0.isCompleted }.count
        }
    }

    func elapsedSeconds(at now: Date) -> Int {
        let end = isSessionPaused ? (sessionPausedAt ?? now) : now
        return max(0, Int(end.timeIntervalSince(startedAt)) - accumulatedSessionPauseSeconds)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.sessionDetail(id: payload.sessionId)
        } catch {
            errorMessage = "训练详情加载失败"
        }
    }

    func toggleSetCompletion(exerciseId: Int, setId: Int) async {
        guard let detail, !savingSetIds.contains(setId) else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let target = contexts.first(where: { $0.exercise.sessionExerciseId == exerciseId && $0.set.sessionSetId == setId }) else { return }
        let shouldStartSet = !target.set.isCompleted && target.set.timerStatus != "running"
        savingSetIds.insert(setId)
        errorMessage = nil
        defer { savingSetIds.remove(setId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                if set.sessionSetId != setId {
                    if shouldStartSet, set.timerStatus == "running" {
                        let elapsed = set.timerStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                        return sessionSetRequest(
                            from: set,
                            exercise: exercise,
                            timerStatusOverride: "idle",
                            clearTimerStartedAt: true,
                            timerAccumulatedSecondsOverride: (set.timerAccumulatedSeconds ?? 0) + elapsed
                        )
                    }
                    if shouldStartSet, set.timerStatus == "paused" {
                        return sessionSetRequest(
                            from: set,
                            exercise: exercise,
                            timerStatusOverride: "idle",
                            clearTimerStartedAt: true
                        )
                    }
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                if set.isCompleted {
                    return sessionSetRequest(
                        from: set,
                        exercise: exercise,
                        isCompletedOverride: false,
                        completedAtOverride: nil,
                        clearCompletedAt: true,
                        timerStatusOverride: "idle",
                        clearTimerStartedAt: true
                    )
                }
                if set.timerStatus == "running" {
                    let elapsed = set.timerStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                    let totalSeconds = (set.timerAccumulatedSeconds ?? 0) + elapsed
                    return sessionSetRequest(
                        from: set,
                        exercise: exercise,
                        isCompletedOverride: true,
                        completedAtOverride: Self.isoFormatter.string(from: .now),
                        timerStatusOverride: "idle",
                        timerAccumulatedSecondsOverride: totalSeconds,
                        actualDurationSecondsOverride: exercise.isTimeBased ? totalSeconds : nil
                    )
                }
                return sessionSetRequest(
                    from: set,
                    exercise: exercise,
                    isCompletedOverride: false,
                    completedAtOverride: nil,
                    timerStatusOverride: "running",
                    timerStartedAtOverride: Self.isoFormatter.string(from: .now)
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            if shouldStartSet {
                if let pausedAt = sessionPausedAt {
                    accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
                }
                sessionPausedAt = nil
                isSessionPaused = false
            }
            await load()
        } catch {
            errorMessage = "保存组状态失败，请检查网络"
        }
    }

    func addSet(to exerciseId: Int) async {
        guard let detail, !savingExerciseIds.contains(exerciseId) else { return }
        savingExerciseIds.insert(exerciseId)
        errorMessage = nil
        defer { savingExerciseIds.remove(exerciseId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                sessionSetRequest(from: set, exercise: exercise)
            } appendedSetForExerciseId: { exercise in
                guard exercise.sessionExerciseId == exerciseId else { return nil }
                let last = exercise.sets.last
                return FitnessSessionSetRequest(
                    sessionSetId: nil,
                    setOrder: exercise.sets.count + 1,
                    setType: last?.setType ?? "normal",
                    plannedWeightKg: last?.plannedWeightKg ?? (exercise.trackingType == "weight_reps" ? 10 : nil),
                    plannedReps: last?.plannedReps ?? (exercise.isTimeBased ? nil : 12),
                    plannedDurationSeconds: last?.plannedDurationSeconds ?? (exercise.isTimeBased ? 30 : nil),
                    plannedDistanceMeters: last?.plannedDistanceMeters ?? (ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType) ? 100 : nil),
                    actualWeightKg: nil,
                    actualReps: nil,
                    actualDurationSeconds: nil,
                    actualDistanceMeters: nil,
                    timerStatus: "idle",
                    timerStartedAt: nil,
                    timerAccumulatedSeconds: 0,
                    rpe: nil,
                    isCompleted: false,
                    completedAt: nil,
                    restSeconds: last?.restSeconds ?? exercise.restSeconds,
                    note: last?.note
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "添加组失败，请检查网络"
        }
    }

    func updateSetValues(exerciseId: Int, setId: Int, actualWeightKg: Double?, actualReps: Int?, actualDurationSeconds: Int?, actualDistanceMeters: Double?) async {
        guard let detail, !updatingSetIds.contains(setId) else { return }
        updatingSetIds.insert(setId)
        errorMessage = nil
        defer { updatingSetIds.remove(setId) }
        do {
            let request = makeStructureRequest(from: detail) { exercise, set in
                guard set.sessionSetId == setId else {
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                return FitnessSessionSetRequest(
                    sessionSetId: set.sessionSetId,
                    setOrder: set.setOrder,
                    setType: set.setType,
                    plannedWeightKg: set.plannedWeightKg,
                    plannedReps: set.plannedReps,
                    plannedDurationSeconds: set.plannedDurationSeconds,
                    plannedDistanceMeters: set.plannedDistanceMeters,
                    actualWeightKg: actualWeightKg,
                    actualReps: actualReps,
                    actualDurationSeconds: actualDurationSeconds,
                    actualDistanceMeters: actualDistanceMeters,
                    timerStatus: set.timerStatus ?? "idle",
                    timerStartedAt: set.timerStartedAt.map { Self.isoFormatter.string(from: $0) },
                    timerAccumulatedSeconds: set.timerAccumulatedSeconds ?? 0,
                    rpe: set.rpe,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt.map { Self.isoFormatter.string(from: $0) },
                    restSeconds: set.restSeconds ?? exercise.restSeconds,
                    note: set.note
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "保存失败，请检查网络"
        }
    }

    func deleteSetFromSession(exerciseId: Int, setId: Int) async {
        guard let detail else { return }
        errorMessage = nil
        do {
            let exerciseRequests = detail.exercises.map { exercise in
                let sets = exercise.sets.filter { $0.sessionSetId != setId }
                    .enumerated()
                    .map { idx, s -> FitnessSessionSetRequest in
                        var req = sessionSetRequest(from: s, exercise: exercise)
                        return FitnessSessionSetRequest(
                            sessionSetId: req.sessionSetId,
                            setOrder: idx + 1,
                            setType: req.setType,
                            plannedWeightKg: req.plannedWeightKg, plannedReps: req.plannedReps,
                            plannedDurationSeconds: req.plannedDurationSeconds, plannedDistanceMeters: req.plannedDistanceMeters,
                            actualWeightKg: req.actualWeightKg, actualReps: req.actualReps,
                            actualDurationSeconds: req.actualDurationSeconds, actualDistanceMeters: req.actualDistanceMeters,
                            timerStatus: req.timerStatus, timerStartedAt: req.timerStartedAt,
                            timerAccumulatedSeconds: req.timerAccumulatedSeconds,
                            rpe: req.rpe, isCompleted: req.isCompleted, completedAt: req.completedAt,
                            restSeconds: req.restSeconds, note: req.note
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
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: [setId]
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "删除组失败，请检查网络"
        }
    }

    func deleteExerciseFromSession(exerciseId: Int) async {
        guard let detail, !savingExerciseIds.contains(exerciseId) else { return }
        savingExerciseIds.insert(exerciseId)
        errorMessage = nil
        defer { savingExerciseIds.remove(exerciseId) }
        do {
            let remainingExercises = detail.exercises.filter { $0.sessionExerciseId != exerciseId }
            let exerciseRequests = remainingExercises.map { exercise in
                FitnessSessionExerciseRequest(
                    sessionExerciseId: exercise.sessionExerciseId,
                    exerciseId: exercise.exerciseId,
                    sortOrder: exercise.sortOrder,
                    restSeconds: exercise.restSeconds,
                    note: exercise.note,
                    sets: exercise.sets.map { sessionSetRequest(from: $0, exercise: exercise) }
                )
            }
            let request = FitnessSessionStructureRequest(
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [exerciseId],
                deletedSessionSetIds: []
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "删除动作失败，请检查网络"
        }
    }

    func addExercisesToSession(_ selected: [FitnessExercise]) async {
        guard let detail, !isAddingExercise else { return }
        let existingExerciseIds = Set(detail.exercises.map { $0.exerciseId })
        let newExercises = selected.filter { !existingExerciseIds.contains($0.id) }
        guard !newExercises.isEmpty else { return }

        isAddingExercise = true
        errorMessage = nil
        defer { isAddingExercise = false }

        do {
            var exerciseRequests = detail.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { exercise in
                    FitnessSessionExerciseRequest(
                        sessionExerciseId: exercise.sessionExerciseId,
                        exerciseId: exercise.exerciseId,
                        sortOrder: exercise.sortOrder,
                        restSeconds: exercise.restSeconds,
                        note: exercise.note,
                        sets: exercise.sets.map { sessionSetRequest(from: $0, exercise: exercise) }
                    )
                }

            let nextSortOrder = (exerciseRequests.map(\.sortOrder).max() ?? 0) + 1
            let appended = newExercises.enumerated().map { offset, exercise in
                FitnessSessionExerciseRequest(
                    sessionExerciseId: nil,
                    exerciseId: exercise.id,
                    sortOrder: nextSortOrder + offset,
                    restSeconds: 120,
                    note: nil,
                    sets: [defaultSessionSetRequest(for: exercise)]
                )
            }
            exerciseRequests.append(contentsOf: appended)

            let request = FitnessSessionStructureRequest(
                exercises: exerciseRequests,
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: []
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "添加动作失败，请检查网络"
        }
    }

    func startNextSet() async {
        guard let target = nextStartTarget() else { return }
        await toggleSetCompletion(exerciseId: target.exerciseId, setId: target.setId)
    }

    func handleMiniPlayerAction() async {
        await waitForPendingSetUpdates()
        if isSessionPaused {
            await resumeSession()
            return
        }
        guard let detail else { return }
        let contexts = orderedSetContexts(from: detail)
        if let running = contexts.first(where: { $0.set.timerStatus == "running" }) {
            await toggleSetCompletion(exerciseId: running.exercise.sessionExerciseId, setId: running.set.sessionSetId)
            return
        }
        await startNextSet()
    }

    func waitForPendingSetUpdates() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
        while !updatingSetIds.isEmpty {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    func pauseSession() async {
        guard !isSessionPaused, !isPausing else { return }
        isSessionPaused = true
        sessionPausedAt = Date()
        await pauseCurrentSet()
    }

    func resumeSession() async {
        guard isSessionPaused else { return }
        let pausedTarget = detail.map { detail in
            orderedSetContexts(from: detail).first { $0.set.timerStatus == "paused" && !$0.set.isCompleted }
        } ?? nil
        if let pausedAt = sessionPausedAt {
            accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
        }
        sessionPausedAt = nil
        isSessionPaused = false
        if let pausedTarget {
            await toggleSetCompletion(exerciseId: pausedTarget.exercise.sessionExerciseId, setId: pausedTarget.set.sessionSetId)
        }
    }

    private func pauseCurrentSet() async {
        guard let detail else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let running = contexts.first(where: { $0.set.timerStatus == "running" }) else { return }
        await pauseSet(setId: running.set.sessionSetId)
    }

    func pauseSet(setId: Int) async {
        guard let detail, !isPausing, !savingSetIds.contains(setId) else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let running = contexts.first(where: { $0.set.sessionSetId == setId && $0.set.timerStatus == "running" }) else { return }
        isPausing = true
        savingSetIds.insert(running.set.sessionSetId)
        errorMessage = nil
        defer {
            isPausing = false
            savingSetIds.remove(running.set.sessionSetId)
        }
        do {
            let now = Date()
            let elapsed = running.set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            let accumulated = (running.set.timerAccumulatedSeconds ?? 0) + elapsed
            let request = makeStructureRequest(from: detail) { exercise, set in
                guard set.sessionSetId == running.set.sessionSetId else {
                    return sessionSetRequest(from: set, exercise: exercise)
                }
                return sessionSetRequest(
                    from: set,
                    exercise: exercise,
                    timerStatusOverride: "paused",
                    timerAccumulatedSecondsOverride: accumulated
                )
            }
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            await load()
        } catch {
            errorMessage = "暂停训练失败，请检查网络"
        }
    }

    func complete(rpe: Double? = nil) async -> Bool {
        guard !isCompleting else { return false }
        isCompleting = true
        errorMessage = nil
        defer { isCompleting = false }
        do {
            _ = try await FitnessAPIClient.completeSession(id: payload.sessionId, rpe: rpe)
            return true
        } catch {
            errorMessage = "完成训练失败，请检查网络"
            return false
        }
    }

    func discard() async -> Bool {
        guard !isDiscarding else { return false }
        isDiscarding = true
        errorMessage = nil
        defer { isDiscarding = false }
        do {
            _ = try await FitnessAPIClient.discardSession(id: payload.sessionId)
            return true
        } catch {
            errorMessage = "删除训练失败，请检查网络"
            return false
        }
    }

    private func nextStartTarget() -> (exerciseId: Int, setId: Int)? {
        guard let detail else { return nil }
        let contexts = orderedSetContexts(from: detail)
        // Same rule the mini player uses so the play button always starts whatever
        // the mini player shows: keep advancing within the current exercise until
        // it's finished, then fall back to any earlier skipped exercise.
        guard let next = fitnessNextTargetContext(in: contexts) else { return nil }
        return (next.exercise.sessionExerciseId, next.set.sessionSetId)
    }

    private func orderedSetContexts(from detail: FitnessSessionDetail) -> [(exercise: FitnessSessionExercise, set: FitnessSessionSet)] {
        detail.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { exercise in
                exercise.sets
                    .sorted { $0.setOrder < $1.setOrder }
                    .map { (exercise: exercise, set: $0) }
            }
    }

    private func makeStructureRequest(
        from detail: FitnessSessionDetail,
        setMapper: (FitnessSessionExercise, FitnessSessionSet) -> FitnessSessionSetRequest,
        appendedSetForExerciseId: ((FitnessSessionExercise) -> FitnessSessionSetRequest?)? = nil
    ) -> FitnessSessionStructureRequest {
        let exerciseRequests = detail.exercises.map { exercise in
            var setRequests = exercise.sets.map { setMapper(exercise, $0) }
            if let appendedSet = appendedSetForExerciseId?(exercise) {
                setRequests.append(appendedSet)
            }
            return FitnessSessionExerciseRequest(
                sessionExerciseId: exercise.sessionExerciseId,
                exerciseId: exercise.exerciseId,
                sortOrder: exercise.sortOrder,
                restSeconds: exercise.restSeconds,
                note: exercise.note,
                sets: setRequests
            )
        }
        return FitnessSessionStructureRequest(
            exercises: exerciseRequests,
            deletedSessionExerciseIds: [],
            deletedSessionSetIds: []
        )
    }

    private func sessionSetRequest(
        from set: FitnessSessionSet,
        exercise: FitnessSessionExercise,
        isCompletedOverride: Bool? = nil,
        completedAtOverride: String? = nil,
        clearCompletedAt: Bool = false,
        timerStatusOverride: String? = nil,
        timerStartedAtOverride: String? = nil,
        clearTimerStartedAt: Bool = false,
        timerAccumulatedSecondsOverride: Int? = nil,
        actualDurationSecondsOverride: Int? = nil
    ) -> FitnessSessionSetRequest {
        let isCompleted = isCompletedOverride ?? set.isCompleted
        let completedAt = clearCompletedAt
            ? nil
            : (isCompleted
                ? (completedAtOverride ?? set.completedAt.map { Self.isoFormatter.string(from: $0) } ?? Self.isoFormatter.string(from: .now))
                : nil)
        let timerStartedAt = clearTimerStartedAt
            ? nil
            : (timerStartedAtOverride ?? set.timerStartedAt.map { Self.isoFormatter.string(from: $0) })
        return FitnessSessionSetRequest(
            sessionSetId: set.sessionSetId,
            setOrder: set.setOrder,
            setType: set.setType,
            plannedWeightKg: set.plannedWeightKg,
            plannedReps: set.plannedReps,
            plannedDurationSeconds: set.plannedDurationSeconds,
            plannedDistanceMeters: set.plannedDistanceMeters,
            actualWeightKg: isCompleted ? (set.actualWeightKg ?? set.plannedWeightKg) : set.actualWeightKg,
            actualReps: isCompleted ? (set.actualReps ?? set.plannedReps) : set.actualReps,
            actualDurationSeconds: isCompleted ? (actualDurationSecondsOverride ?? set.actualDurationSeconds ?? set.plannedDurationSeconds) : set.actualDurationSeconds,
            actualDistanceMeters: isCompleted ? (set.actualDistanceMeters ?? set.plannedDistanceMeters) : set.actualDistanceMeters,
            timerStatus: timerStatusOverride ?? set.timerStatus ?? "idle",
            timerStartedAt: timerStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSecondsOverride ?? set.timerAccumulatedSeconds ?? 0,
            rpe: set.rpe,
            isCompleted: isCompleted,
            completedAt: completedAt,
            restSeconds: set.restSeconds ?? exercise.restSeconds,
            note: set.note
        )
    }

    private func defaultSessionSetRequest(for exercise: FitnessExercise) -> FitnessSessionSetRequest {
        FitnessSessionSetRequest(
            sessionSetId: nil,
            setOrder: 1,
            setType: "normal",
            plannedWeightKg: exercise.trackingType == "weight_reps" ? 10 : nil,
            plannedReps: exercise.isTimeBased ? nil : 12,
            plannedDurationSeconds: exercise.isTimeBased ? 30 : nil,
            plannedDistanceMeters: ExerciseTrackingDisplay.isDistanceBased(exercise.trackingType) ? 100 : nil,
            actualWeightKg: nil,
            actualReps: nil,
            actualDurationSeconds: nil,
            actualDistanceMeters: nil,
            timerStatus: "idle",
            timerStartedAt: nil,
            timerAccumulatedSeconds: 0,
            rpe: nil,
            isCompleted: false,
            completedAt: nil,
            restSeconds: 120,
            note: nil
        )
    }
}
