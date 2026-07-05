import Foundation
import Combine
import HealthKit

/// Drives an `HKWorkoutSession` for the duration of a strength workout so the watch
/// can surface live heart rate and active energy, and the workout is recorded to
/// HealthKit (which the phone's existing health sync then uploads to the backend).
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    /// Shared instance so the workout (and its async save) survives the active
    /// view being torn down.
    static let shared = WatchWorkoutManager()

    @Published private(set) var heartRate: Int = 0
    @Published private(set) var activeEnergyKcal: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The backend session this workout belongs to, stamped into the saved
    /// HKWorkout's metadata so it can later be found and deleted by session.
    private var sessionId: Int?

    /// Metadata key linking a saved HKWorkout back to our backend session id.
    static let sessionMetadataKey = "knowing_session_id"

    /// When the session actually started, so `end()` can reject workouts too
    /// short to be real (mis-taps / quick tests) instead of saving 0:00 junk.
    private var startDate: Date?
    private static let minimumSaveSeconds: TimeInterval = 10

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
    }
    private static var shareTypes: Set<HKSampleType> { [HKQuantityType.workoutType()] }

    /// Ask for the HealthKit permissions the live session needs, once at app
    /// launch so the confirmation is out of the way before the user starts a
    /// workout. Best-effort — a denial just means we show 0 for HR/energy, the
    /// workout flow still works.
    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let status = try? await authorizationRequestStatus(store: store, toShare: shareTypes, read: readTypes)
        guard status == .shouldRequest else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    private static func authorizationRequestStatus(
        store: HKHealthStore,
        toShare shareTypes: Set<HKSampleType>,
        read readTypes: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func start(sessionId: Int) {
        self.sessionId = sessionId
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let start = Date()
            startDate = start
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            // Reset live metrics from any previous session (singleton is reused).
            heartRate = 0
            activeEnergyKcal = 0
            isPaused = false
            isRunning = true
        } catch {
            session = nil
            builder = nil
        }
    }

    func pause() {
        session?.pause()
        isPaused = true
    }

    func resume() {
        session?.resume()
        isPaused = false
    }

    func end() {
        guard let session, let builder else {
            isRunning = false
            return
        }
        // Claim the session/builder synchronously so a second end() — e.g. the
        // explicit end on completion followed by onDisappear's end — becomes a
        // no-op instead of finishing (and saving) the workout twice.
        self.session = nil
        self.builder = nil
        isRunning = false

        session.end()

        // Too short to be a real workout — discard rather than save 0:00 junk.
        let elapsed = startDate.map { Date().timeIntervalSince($0) } ?? 0
        startDate = nil
        guard elapsed >= Self.minimumSaveSeconds else {
            builder.discardWorkout()
            return
        }

        let metadata: [String: Any] = sessionId.map { [Self.sessionMetadataKey: $0] } ?? [:]
        let finish: () -> Void = {
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { _, _ in
                    // Retain the session until the save completes so it isn't
                    // torn down mid-write.
                    withExtendedLifetime(session) {}
                }
            }
        }
        if metadata.isEmpty {
            finish()
        } else {
            builder.addMetadata(metadata) { _, _ in finish() }
        }
    }

    /// Delete the HKWorkout saved for `sessionId`. Only the watch app can delete
    /// the workouts it wrote, so this is how "删除本次训练" removes the Apple
    /// Health record. A no-op if nothing matches (e.g. a discarded session that
    /// was never saved).
    static func deleteWorkout(sessionId: Int) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(withMetadataKey: sessionMetadataKey, allowedValues: [sessionId])
        let workouts: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
        guard !workouts.isEmpty else { return }
        try? await store.delete(workouts)
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        startDate = nil
        isRunning = false
        isPaused = false
        heartRate = 0
        activeEnergyKcal = 0
    }

    fileprivate func ingest(_ statistics: HKStatistics?) {
        guard let statistics else { return }
        if statistics.quantityType == HKQuantityType(.heartRate) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                heartRate = Int(bpm.rounded())
            }
        } else if statistics.quantityType == HKQuantityType(.activeEnergyBurned) {
            let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            if let kcal { activeEnergyKcal = kcal }
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            Task { @MainActor in self.ingest(statistics) }
        }
    }
}
