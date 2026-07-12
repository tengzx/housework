import SwiftUI
import Combine
import UIKit
import AudioToolbox

/// Snapshot of what the mini player should show. Shared by the full workout
/// screen's bottom bar and the collapsed tab-bar accessory so they stay in sync.
struct WorkoutMiniPlayerState {
    let title: String
    let prefix: String
    let timeText: String
    let tint: Color
    let actionSymbol: String
    let actionFill: Color
    let actionForeground: Color
    let actionDisabled: Bool
    let restDueSetId: Int?
    var isFinishAction: Bool = false
}


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
    @Published private(set) var isReorderingExercises = false
    @Published private(set) var isSessionPaused = false
    @Published private(set) var savingSetIds: Set<Int> = []
    @Published private(set) var updatingSetIds: Set<Int> = []
    @Published private(set) var savingExerciseIds: Set<Int> = []
    @Published var errorMessage: String?

    private var sessionPausedAt: Date?
    private var accumulatedSessionPauseSeconds = 0
    private var needsReloadAfterCurrentLoad = false
    private var pendingOperations: [FitnessSessionOperationRequest] = []
    private var isFlushingOperations = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(payload: FitnessWorkoutSessionPayload) {
        self.payload = payload
        self.pendingOperations = Self.loadPendingOperations(sessionId: payload.sessionId)
        Task { await flushPendingOperations() }
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
        if isLoading {
            needsReloadAfterCurrentLoad = true
            return
        }

        repeat {
            needsReloadAfterCurrentLoad = false
            isLoading = true
            errorMessage = nil
            do {
                detail = try await FitnessAPIClient.sessionDetail(id: payload.sessionId)
            } catch {
                errorMessage = SharedL10n.tr("fitness.session.load_failed")
            }
            isLoading = false
        } while needsReloadAfterCurrentLoad
    }

    func toggleSetCompletion(exerciseId: Int, setId: Int) async {
        guard let detail, !savingSetIds.contains(setId) else { return }
        let contexts = orderedSetContexts(from: detail)
        guard let target = contexts.first(where: { $0.exercise.sessionExerciseId == exerciseId && $0.set.sessionSetId == setId }) else { return }
        let now = Date()
        let operation: FitnessSessionOperationRequest
        if target.set.isCompleted {
            operation = makeOperation(type: "reopen_set", setId: setId, now: now)
        } else if target.set.timerStatus == "running" {
            let elapsed = (target.set.timerAccumulatedSeconds ?? 0) + (target.set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0)
            operation = makeOperation(
                type: "complete_set",
                setId: setId,
                actualWeightKg: target.set.actualWeightKg ?? target.set.plannedWeightKg,
                actualReps: target.set.actualReps ?? target.set.plannedReps,
                actualDurationSeconds: target.exercise.isTimeBased ? elapsed : (target.set.actualDurationSeconds ?? target.set.plannedDurationSeconds),
                actualDistanceMeters: target.set.actualDistanceMeters ?? target.set.plannedDistanceMeters,
                now: now
            )
        } else {
            operation = makeOperation(type: "start_set", setId: setId, now: now)
        }

        applyOptimistic(operation)
        broadcastCurrentSnapshot()
        enqueueOperation(operation)
        if operation.type == "start_set" {
            if let pausedAt = sessionPausedAt {
                accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
            }
            sessionPausedAt = nil
            isSessionPaused = false
        }
    }

    private func saveSetCompletionViaStructure(exerciseId: Int, setId: Int) async {
        await waitForPendingLoad()
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
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            if shouldStartSet {
                if let pausedAt = sessionPausedAt {
                    accumulatedSessionPauseSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
                }
                sessionPausedAt = nil
                isSessionPaused = false
            }
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.save_set_failed")
        }
    }

    func addSet(to exerciseId: Int) async {
        await waitForPendingLoad()
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
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.add_set_failed")
        }
    }

    func updateSetValues(exerciseId: Int, setId: Int, actualWeightKg: Double?, actualReps: Int?, actualDurationSeconds: Int?, actualDistanceMeters: Double?) async {
        guard let detail, !updatingSetIds.contains(setId) else { return }
        guard orderedSetContexts(from: detail).contains(where: { $0.exercise.sessionExerciseId == exerciseId && $0.set.sessionSetId == setId }) else { return }
        let operation = makeOperation(
            type: "update_set_values",
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

    func deleteSetFromSession(exerciseId: Int, setId: Int) async {
        await waitForPendingLoad()
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
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.delete_set_failed")
        }
    }

    func deleteExerciseFromSession(exerciseId: Int) async {
        await waitForPendingLoad()
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
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.delete_exercise_failed")
        }
    }

    func addExercisesToSession(_ selected: [FitnessExercise]) async {
        await waitForPendingLoad()
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
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.add_exercise_failed")
        }
    }

    /// Reorder exercises via long-press drag. The list is updated optimistically
    /// (so it doesn't snap back while the save round-trips), sort orders are
    /// renumbered to match the new arrangement, then the full structure is saved.
    func moveExercise(from source: IndexSet, to destination: Int) async {
        await waitForPendingLoad()
        guard let detail, !isReorderingExercises else { return }
        var reordered = detail.exercises
        reordered.move(fromOffsets: source, toOffset: destination)
        let renumbered = reordered.enumerated().map { index, exercise in
            exercise.reordered(sortOrder: index + 1)
        }
        // Optimistic update so the rows stay in the dropped position.
        self.detail = detail.replacingExercises(renumbered)

        isReorderingExercises = true
        errorMessage = nil
        defer { isReorderingExercises = false }
        do {
            let exerciseRequests = renumbered.map { exercise in
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
                deletedSessionExerciseIds: [],
                deletedSessionSetIds: []
            )
            _ = try await FitnessAPIClient.saveSessionStructure(id: payload.sessionId, request: request)
            PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
            await load()
        } catch {
            errorMessage = SharedL10n.tr("fitness.session.reorder_failed")
            await load()
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

    private func waitForPendingLoad() async {
        while isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
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
        let operation = makeOperation(type: "pause_set", setId: running.set.sessionSetId)
        applyOptimistic(operation)
        broadcastCurrentSnapshot()
        enqueueOperation(operation)
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
            if FitnessAPIClient.isMissingResourceError(error) {
                return true
            }
            errorMessage = SharedL10n.tr("fitness.session.complete_failed")
            return false
        }
    }

    /// Save the template to match what was actually performed this session, then
    /// complete the session. Only meaningful when the session came from a
    /// template (`detail.templateId != nil`).
    func completeAndUpdateTemplate(rpe: Double? = nil) async -> Bool {
        guard !isCompleting else { return false }
        isCompleting = true
        errorMessage = nil
        defer { isCompleting = false }
        do {
            // Update the template first so a failure here doesn't leave a
            // completed session with a stale template; completion follows only
            // once the template is saved.
            if let detail, let templateId = detail.templateId {
                let existing = try await FitnessAPIClient.templateDetail(id: templateId)
                let request = Self.templateStructureRequest(from: detail, existing: existing)
                _ = try await FitnessAPIClient.saveTemplateStructure(id: templateId, request: request)
            }
            _ = try await FitnessAPIClient.completeSession(id: payload.sessionId, rpe: rpe)
            return true
        } catch {
            if FitnessAPIClient.isMissingResourceError(error) {
                return true
            }
            errorMessage = SharedL10n.tr("fitness.session.complete_update_template_failed")
            return false
        }
    }

    /// Rebuild the template structure from a finished session: the exercises and
    /// sets performed become the new template, using each set's actual values
    /// (falling back to planned) as the new targets. Existing template exercises
    /// are deleted so the template ends up mirroring the session exactly.
    private static func templateStructureRequest(
        from detail: FitnessSessionDetail,
        existing: FitnessTemplateDetail
    ) -> SaveTemplateStructureRequest {
        let exercises = detail.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, ex -> SaveExerciseItem in
                let timeBased = ExerciseTrackingDisplay.isTimeBased(ex.trackingType)
                let distanceBased = ExerciseTrackingDisplay.isDistanceBased(ex.trackingType)
                let sets = ex.sets
                    .sorted { $0.setOrder < $1.setOrder }
                    .enumerated()
                    .map { setIndex, set -> SaveSetItem in
                        SaveSetItem(
                            templateSetId: nil,
                            setOrder: setIndex + 1,
                            setType: set.setType,
                            targetWeightKg: timeBased ? nil : (set.actualWeightKg ?? set.plannedWeightKg),
                            targetReps: timeBased ? nil : (set.actualReps ?? set.plannedReps),
                            targetDurationSeconds: timeBased ? (set.actualDurationSeconds ?? set.plannedDurationSeconds) : nil,
                            targetDistanceMeters: distanceBased ? (set.actualDistanceMeters ?? set.plannedDistanceMeters) : nil,
                            restSeconds: set.restSeconds ?? ex.restSeconds,
                            note: set.note ?? ""
                        )
                    }
                return SaveExerciseItem(
                    templateExerciseId: nil,
                    exerciseId: ex.exerciseId,
                    sortOrder: index + 1,
                    restSeconds: ex.restSeconds,
                    note: ex.note ?? "",
                    sets: sets
                )
            }
        return SaveTemplateStructureRequest(
            exercises: exercises,
            deletedTemplateExerciseIds: existing.exercises.map { $0.templateExerciseId },
            deletedTemplateSetIds: []
        )
    }

    func discard() async -> Bool {
        guard !isDiscarding else { return false }
        isDiscarding = true
        errorMessage = nil
        defer { isDiscarding = false }
        do {
            _ = try await FitnessAPIClient.discardSession(id: payload.sessionId)
            // Also remove the Apple Health workout the watch saved for this
            // session (only the watch can delete its own workouts).
            PhoneWatchSync.shared.requestWorkoutDeletion(sessionId: payload.sessionId)
            return true
        } catch {
            if FitnessAPIClient.isMissingResourceError(error) {
                PhoneWatchSync.shared.requestWorkoutDeletion(sessionId: payload.sessionId)
                return true
            }
            errorMessage = SharedL10n.tr("fitness.session.discard_failed")
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

    // MARK: Mini player state

    /// The state driving the mini player — shown both at the bottom of the full
    /// workout screen and in the collapsed tab-bar accessory, so they stay in sync.
    func miniPlayerState(now: Date) -> WorkoutMiniPlayerState {
        guard let detail else {
            return WorkoutMiniPlayerState(
                title: title, prefix: "----", timeText: "00:00",
                tint: Color(hex: "4B8CFF"), actionSymbol: "play.fill",
                actionFill: .white, actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: true, restDueSetId: nil
            )
        }

        let contexts = orderedSetContexts(from: detail)
        if isSessionPaused {
            let paused = contexts.first { $0.set.timerStatus == "paused" && !$0.set.isCompleted }
            return WorkoutMiniPlayerState(
                title: paused?.exercise.name ?? detail.name,
                prefix: SharedL10n.tr("fitness.session.prefix.paused_workout"),
                timeText: paused.map { Self.clockText($0.set.timerAccumulatedSeconds ?? 0) } ?? Self.clockText(elapsedSeconds(at: now)),
                tint: Color(hex: "8E8E93"), actionSymbol: "play.fill",
                actionFill: .white, actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: isPausing, restDueSetId: nil
            )
        }

        if let running = contexts.first(where: { $0.set.timerStatus == "running" }) {
            let base = running.set.timerAccumulatedSeconds ?? 0
            let live = running.set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            return WorkoutMiniPlayerState(
                title: running.exercise.name, prefix: SharedL10n.tr("fitness.session.prefix.active"),
                timeText: Self.clockText(base + live),
                tint: Color(hex: "FF7847"), actionSymbol: "checkmark",
                actionFill: Color(hex: "34C982"), actionForeground: .white,
                actionDisabled: savingSetIds.contains(running.set.sessionSetId), restDueSetId: nil
            )
        }

        if let paused = contexts.first(where: { $0.set.timerStatus == "paused" && !$0.set.isCompleted }) {
            return WorkoutMiniPlayerState(
                title: paused.exercise.name, prefix: SharedL10n.tr("fitness.session.prefix.paused"),
                timeText: Self.clockText(paused.set.timerAccumulatedSeconds ?? 0),
                tint: Color(hex: "8E8E93"), actionSymbol: "play.fill",
                actionFill: .white, actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: savingSetIds.contains(paused.set.sessionSetId), restDueSetId: nil
            )
        }

        let lastCompleted = contexts
            .filter { $0.set.isCompleted }
            .max { ($0.set.completedAt ?? .distantPast) < ($1.set.completedAt ?? .distantPast) }
        if let lastCompleted,
           let completedAt = lastCompleted.set.completedAt,
           let next = fitnessNextTargetContext(in: contexts),
           !Self.hasSetStarted(next.set) {
            let restSeconds = lastCompleted.set.restSeconds ?? lastCompleted.exercise.restSeconds
            let elapsed = max(0, Int(now.timeIntervalSince(completedAt)))
            let remaining = max(0, restSeconds - elapsed)
            return WorkoutMiniPlayerState(
                title: next.exercise.name,
                prefix: remaining == 0 ? SharedL10n.tr("fitness.session.prefix.rest_done") : SharedL10n.tr("fitness.session.prefix.resting"),
                timeText: Self.clockText(remaining),
                tint: remaining == 0 ? Color(hex: "34C982") : Color(hex: "4B8CFF"),
                actionSymbol: "play.fill",
                // Start button stays white (green is only for the complete action);
                // the "休息完成" cue is conveyed by the green prefix text above.
                actionFill: .white,
                actionForeground: Color(hex: "1C1C1E"),
                actionDisabled: false,
                restDueSetId: remaining == 0 ? lastCompleted.set.sessionSetId : nil
            )
        }

        let next = contexts.first { !$0.set.isCompleted && $0.set.timerStatus != "running" }
        if next == nil && !contexts.isEmpty {
            return WorkoutMiniPlayerState(
                title: detail.name, prefix: SharedL10n.tr("common.done"),
                timeText: Self.clockText(elapsedSeconds(at: now)),
                tint: Color(hex: "34C982"), actionSymbol: "flag.checkered",
                actionFill: Color(hex: "34C982"), actionForeground: .white,
                actionDisabled: isCompleting, restDueSetId: nil, isFinishAction: true
            )
        }

        return WorkoutMiniPlayerState(
            title: next?.exercise.name ?? detail.name, prefix: SharedL10n.tr("fitness.session.prefix.ready"),
            timeText: "00:00", tint: Color(hex: "4B8CFF"), actionSymbol: "play.fill",
            actionFill: .white, actionForeground: Color(hex: "1C1C1E"),
            actionDisabled: next == nil, restDueSetId: nil
        )
    }

    static func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func hasSetStarted(_ set: FitnessSessionSet) -> Bool {
        set.timerStartedAt != nil
            || (set.timerAccumulatedSeconds ?? 0) > 0
            || set.timerStatus == "running"
            || set.timerStatus == "paused"
            || set.isCompleted
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
            clientTime: Self.isoFormatter.string(from: now)
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
                let fresh = try await FitnessAPIClient.applySessionOperation(id: payload.sessionId, request: operation)
                pendingOperations.removeFirst()
                persistPendingOperations()
                detail = fresh
                PhoneWatchSync.shared.broadcastSessionSnapshot(fresh)
                PhoneWatchSync.shared.broadcastSessionChanged(payload.sessionId)
                errorMessage = nil
            } catch {
                errorMessage = SharedL10n.tr("fitness.session.pending_retry")
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
            UserDefaults.standard.set(data, forKey: Self.pendingOperationsKey(sessionId: payload.sessionId))
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
        "fitness.pendingOperations.\(sessionId)"
    }

    private func applyOptimistic(_ operation: FitnessSessionOperationRequest) {
        guard let detail else { return }
        let now = Self.isoFormatter.date(from: operation.clientTime) ?? .now
        let exercises = detail.exercises.map { exercise in
            let sets = exercise.sets.map { set in
                optimisticSet(set, exercise: exercise, operation: operation, now: now)
            }
            return exercise.replacingSets(sets)
        }
        self.detail = detail.replacingExercises(exercises)
    }

    func applyRemoteSnapshot(_ snapshot: FitnessSessionDetail) {
        guard snapshot.id == payload.sessionId else { return }
        detail = snapshot
    }

    private func broadcastCurrentSnapshot() {
        guard let detail else { return }
        PhoneWatchSync.shared.broadcastSessionSnapshot(detail)
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
                return set.replacing(timerStatus: "running", timerStartedAt: now, timerAccumulatedSeconds: set.timerAccumulatedSeconds ?? 0, isCompleted: false, completedAt: nil)
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
        case "pause_set":
            let elapsed = set.timerStartedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            return set.replacing(timerStatus: "paused", clearTimerStartedAt: true, timerAccumulatedSeconds: (set.timerAccumulatedSeconds ?? 0) + elapsed)
        case "update_set_values":
            return set.replacing(
                actualWeightKg: operation.actualWeightKg,
                actualReps: operation.actualReps,
                actualDurationSeconds: operation.actualDurationSeconds,
                actualDistanceMeters: operation.actualDistanceMeters,
                rpe: operation.rpe ?? set.rpe
            )
        default:
            return set
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

// MARK: - Reorder copy helpers

private extension FitnessSessionExercise {
    /// A copy of the exercise with a new `sortOrder`, used when reordering.
    func reordered(sortOrder newOrder: Int) -> FitnessSessionExercise {
        FitnessSessionExercise(
            sessionExerciseId: sessionExerciseId,
            exerciseId: exerciseId,
            name: name,
            trackingType: trackingType,
            exerciseType: exerciseType,
            imageUrl: imageUrl,
            sortOrder: newOrder,
            restSeconds: restSeconds,
            note: note,
            sets: sets
        )
    }

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

private extension FitnessSessionDetail {
    /// A copy of the session detail with its exercises replaced, used to reflect
    /// a reorder optimistically before the server round-trip completes.
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
