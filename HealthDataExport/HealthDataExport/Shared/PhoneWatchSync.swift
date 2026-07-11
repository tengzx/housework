import Foundation
import WatchConnectivity

/// A workout session shared between the phone and watch.
struct WorkoutSyncPayload: Equatable {
    let sessionId: Int
    let name: String
}

/// Bridges state between the iPhone and the paired Apple Watch:
///
/// 1. Pushes the logged-in bearer token so the watch can authenticate.
/// 2. Mirrors the *active workout session* both ways — starting a workout on one
///    device opens it on the other, and finishing it closes it everywhere.
///
/// The active session is versioned with a timestamp: whichever device changed it
/// most recently wins, so the two converge without echo loops (a device that
/// *adopts* a remote change copies its version rather than bumping its own).
final class PhoneWatchSync: NSObject {
    static let shared = PhoneWatchSync()

    /// Invoked when the *watch* changes the active session: non-nil to open it,
    /// nil to close it. Set by the app root; hops to the main actor itself.
    nonisolated(unsafe) var onRemoteWorkout: ((WorkoutSyncPayload?) -> Void)?

    /// Invoked when the watch mutates a session's sets (start/complete/edit) so the
    /// phone can reload that session from the server. Carries the sessionId.
    nonisolated(unsafe) var onRemoteSessionChanged: ((Int) -> Void)?
    nonisolated(unsafe) var onRemoteSessionSnapshot: ((Int, FitnessSessionDetail) -> Void)?
    nonisolated(unsafe) var onRemoteSessionCompleted: ((Int) -> Void)?

    /// Invoked with the watch's live heart rate: (sessionId, bpm).
    nonisolated(unsafe) var onRemoteHeartRate: ((Int, Int) -> Void)?

    /// Invoked when the *watch* changes the active time-tracking entry (nil = stopped),
    /// so the phone can update its own record store.
    nonisolated(unsafe) var onRemoteTimeEntry: ((SharedActiveActivity?) -> Void)?

    private let lock = NSLock()
    private var authContext: [String: Any] = [:]

    // Shared active-session state.
    private var wkVersion: Double = 0
    private var wkSession: WorkoutSyncPayload?

    // In-session change pings (start/complete/edit a set).
    private var wkChangeStamp: Double = 0
    private var wkChangedSession: Int?
    private var lastSeenChangeStamp: Double = 0
    private var wkSnapshotStamp: Double = 0
    private var wkSnapshotSession: Int?
    private var wkSnapshotData: Data?
    private var lastSeenSnapshotStamp: Double = 0

    // Active time-tracking entry, mirrored to the watch's face complication.
    private var teStamp: Double = 0
    private var teData: Data?
    private var lastSeenTeStamp: Double = 0
    /// Set when a broadcast happens before the session is activated, so
    /// activation can send the missed transfer (and only then — re-transferring
    /// on every activation would drain the complication budget for nothing).
    private var teTransferPending = false
    /// Persisted so a relaunch still knows which watch states it already
    /// applied — queued transfers can replay across process lifetimes.
    private static let teSeenStampKey = "phoneWatchSync.teStamp.lastSeen"

    private override init() {
        super.init()
        lastSeenTeStamp = UserDefaults.standard.double(forKey: Self.teSeenStampKey)
    }

    private static let relayEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let relayDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: rawValue) ?? standard.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(rawValue)"
            )
        }
        return decoder
    }()

    /// Activate the shared `WCSession`. Safe to call more than once.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Auth

    /// Update the auth context and push it to the watch. Pass `token: nil` on logout.
    func updateSession(token: String?, userId: Int?, nickname: String?) {
        var ctx: [String: Any] = [:]
        if let token, !token.trimmingCharacters(in: .whitespaces).isEmpty {
            ctx["authToken"] = token
        }
        if let userId { ctx["userId"] = userId }
        if let nickname, !nickname.isEmpty { ctx["nickname"] = nickname }

        lock.lock(); authContext = ctx; lock.unlock()
        pushIfPossible()
    }

    // MARK: Time tracking

    /// Mirror the phone's active time-tracking entry to the watch (nil = stopped),
    /// so the watch-face complication updates even when the change happened on the
    /// phone. Versioned with a timestamp like the workout state.
    func broadcastTimeEntry(_ activity: SharedActiveActivity?) {
        lock.lock()
        teStamp = max(teStamp + 0.001, Date().timeIntervalSince1970)
        teData = activity.flatMap { try? Self.relayEncoder.encode($0) }
        teTransferPending = true
        lock.unlock()
        pushIfPossible()
        transferTimeEntry()
        sendWorkoutMessage()
    }

    // MARK: Workout

    /// Broadcast a local active-session change (started/opened, or nil = ended).
    func broadcastWorkout(_ payload: WorkoutSyncPayload?) {
        lock.lock()
        wkVersion = max(wkVersion + 0.001, Date().timeIntervalSince1970)
        wkSession = payload
        lock.unlock()
        pushIfPossible()
        sendWorkoutMessage()
    }

    /// Clear the active workout only if it still points at the completed/deleted
    /// session. This prevents an old relay reply from closing a newer workout.
    @discardableResult
    private func clearWorkoutIfCurrent(sessionId: Int) -> Bool {
        lock.lock()
        guard wkSession?.sessionId == sessionId else {
            lock.unlock()
            return false
        }
        wkVersion = max(wkVersion + 0.001, Date().timeIntervalSince1970)
        wkSession = nil
        if wkChangedSession == sessionId {
            wkChangedSession = nil
        }
        if wkSnapshotSession == sessionId {
            wkSnapshotSession = nil
            wkSnapshotData = nil
        }
        lock.unlock()
        pushIfPossible()
        sendWorkoutMessage()
        onRemoteWorkout?(nil)
        return true
    }

    /// The workout the watch currently has active (if any), as last received.
    /// Used by the app root to catch up if it launched *after* the watch started
    /// a session (the callback wasn't set when the context first arrived).
    func currentWorkout() -> WorkoutSyncPayload? {
        lock.lock(); defer { lock.unlock() }
        return wkSession
    }

    /// Re-process the last application context the watch delivered. Safe to call
    /// once the app root is ready, in case activation happened earlier.
    func refreshFromContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        handleRemoteWorkout(session.receivedApplicationContext)
    }

    private func handleRemoteWorkout(_ dict: [String: Any]) {
        if let version = dict["wkVersion"] as? Double {
            lock.lock()
            if version > wkVersion {
                wkVersion = version
                let payload = (dict["wkSessionId"] as? Int).map {
                    WorkoutSyncPayload(sessionId: $0, name: dict["wkName"] as? String ?? "")
                }
                wkSession = payload
                lock.unlock()
                onRemoteWorkout?(payload)
            } else {
                lock.unlock()
            }
        }
        handleRemoteChange(dict)
        handleRemoteSnapshot(dict)
        handleRemoteTimeEntry(dict)
        if let bpm = dict["wkHeartRate"] as? Int, let sessionId = dict["wkHrSession"] as? Int {
            onRemoteHeartRate?(sessionId, bpm)
        }
    }

    /// A time-tracking entry change arrived from the watch. Versioned so an older
    /// message can't overwrite a newer state.
    private func handleRemoteTimeEntry(_ dict: [String: Any]) {
        guard let stamp = dict["teStamp"] as? Double else { return }
        let data = dict["teData"] as? Data
        lock.lock()
        guard stamp > lastSeenTeStamp else { lock.unlock(); return }
        lastSeenTeStamp = stamp
        UserDefaults.standard.set(stamp, forKey: Self.teSeenStampKey)
        // A queued transfer can arrive long after it was sent — never let a
        // remote state older than our own latest local change overwrite it.
        guard stamp > teStamp else { lock.unlock(); return }
        teStamp = stamp
        teData = data
        lock.unlock()
        let activity = data.flatMap {
            try? Self.relayDecoder.decode(SharedActiveActivity.self, from: $0)
        }
        onRemoteTimeEntry?(activity)
    }

    /// Broadcast that a session's sets changed so the other device reloads it.
    func broadcastSessionChanged(_ sessionId: Int) {
        lock.lock()
        wkChangeStamp = max(wkChangeStamp + 0.001, Date().timeIntervalSince1970)
        wkChangedSession = sessionId
        lock.unlock()
        pushIfPossible()
        sendWorkoutMessage()
    }

    func broadcastSessionSnapshot(_ detail: FitnessSessionDetail) {
        guard let data = try? Self.relayEncoder.encode(detail) else { return }
        lock.lock()
        wkSnapshotStamp = max(wkSnapshotStamp + 0.001, Date().timeIntervalSince1970)
        wkSnapshotSession = detail.id
        wkSnapshotData = data
        lock.unlock()
        pushIfPossible()
        sendWorkoutMessage()
    }

    private func handleRemoteChange(_ dict: [String: Any]) {
        guard let stamp = dict["wkChangeStamp"] as? Double,
              let sessionId = dict["wkChangedSession"] as? Int else { return }
        lock.lock()
        guard stamp > lastSeenChangeStamp else { lock.unlock(); return }
        lastSeenChangeStamp = stamp
        lock.unlock()
        onRemoteSessionChanged?(sessionId)
    }

    private func handleRemoteSnapshot(_ dict: [String: Any]) {
        guard let stamp = dict["wkSnapshotStamp"] as? Double,
              let sessionId = dict["wkSnapshotSession"] as? Int,
              let data = dict["wkSnapshotDetail"] as? Data else { return }
        lock.lock()
        guard stamp > lastSeenSnapshotStamp else { lock.unlock(); return }
        lastSeenSnapshotStamp = stamp
        lock.unlock()
        guard let detail = try? Self.relayDecoder.decode(FitnessSessionDetail.self, from: data) else { return }
        onRemoteSessionSnapshot?(sessionId, detail)
    }

    // MARK: Delivery

    private func mergedContext() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var ctx = authContext
        if wkVersion > 0 {
            ctx["wkVersion"] = wkVersion
            if let session = wkSession {
                ctx["wkSessionId"] = session.sessionId
                ctx["wkName"] = session.name
            }
        }
        if wkChangeStamp > 0, let changed = wkChangedSession {
            ctx["wkChangeStamp"] = wkChangeStamp
            ctx["wkChangedSession"] = changed
        }
        if wkSnapshotStamp > 0, let sessionId = wkSnapshotSession, let data = wkSnapshotData {
            ctx["wkSnapshotStamp"] = wkSnapshotStamp
            ctx["wkSnapshotSession"] = sessionId
            ctx["wkSnapshotDetail"] = data
        }
        if teStamp > 0 {
            ctx["teStamp"] = teStamp
            if let data = teData { ctx["teData"] = data }
        }
        return ctx
    }

    private func pushIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var ctx = mergedContext()
        // A marker so an otherwise-identical context (e.g. logout) still delivers.
        ctx["updatedAt"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(ctx)
    }

    private func sendWorkoutMessage() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(mergedContext(), replyHandler: nil, errorHandler: nil)
    }

    private func transferTimeEntry() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Build a MINIMAL, dedicated payload — only the time-entry keys. The full
        // `mergedContext()` also carries `wkSnapshotDetail` (a whole session's JSON,
        // several KB), which once broadcast lingers on this singleton for the app's
        // lifetime. A complication transfer has a strict size limit, so bundling
        // that heavy data risks the transfer silently failing — meaning a *stop*
        // never reaches the watch and the face keeps counting until the app is
        // opened. Keep this transfer tiny so it reliably lands.
        lock.lock()
        guard teTransferPending, teStamp > 0 else { lock.unlock(); return }
        teTransferPending = false
        let stamp = teStamp
        let data = teData
        lock.unlock()

        // Only the latest state matters — cancel queued-but-undelivered
        // time-entry transfers so they can't replay an older start/stop after
        // this one, and so stale entries don't drain the daily complication
        // budget when they finally deliver.
        for transfer in session.outstandingUserInfoTransfers where transfer.userInfo["teStamp"] != nil {
            transfer.cancel()
        }

        var payload: [String: Any] = ["teStamp": stamp]
        if let data { payload["teData"] = data }

        if session.isReachable {
            // The watch app is in the foreground: the live `sendMessage` in
            // `broadcastTimeEntry` already delivered this state and refreshed
            // the face. Don't spend complication budget — queue a plain
            // transfer as a durable backup in case the message was dropped
            // (the receiver dedupes by `teStamp`, so a double-delivery is a
            // no-op).
            session.transferUserInfo(payload)
        } else if session.remainingComplicationUserInfoTransfers > 0 {
            // A complication transfer launches the watch app in the BACKGROUND
            // to deliver the payload, so the face refreshes without the user
            // opening the app — including overnight / under Sleep Focus. Gate on
            // the remaining daily budget rather than `isComplicationEnabled`:
            // the latter is unreliable for WidgetKit complications, while the
            // budget is 0 whenever the complication isn't on the active face.
            session.transferCurrentComplicationUserInfo(payload)
        } else {
            // No budget (or complication not on the face): fall back to a
            // durable queued transfer, delivered next time the watch app runs.
            session.transferUserInfo(payload)
        }
    }

    /// Ask the watch to delete the Apple Health workout it saved for `sessionId`.
    /// Only the watch can delete workouts it wrote, so deleting a session on the
    /// phone routes the HealthKit cleanup here. `transferUserInfo` queues the
    /// request so it survives the watch being unreachable at delete time; a
    /// direct message is also sent for immediacy when the watch is awake.
    func requestWorkoutDeletion(sessionId: Int) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(["deleteWorkoutSession": sessionId])
        if session.isReachable {
            session.sendMessage(["deleteWorkoutSession": sessionId], replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleFitnessRelay(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = message["fitnessRelayCommand"] as? String,
              let sessionId = message["sessionId"] as? Int else {
            replyHandler(["ok": false, "error": "bad_request"])
            return
        }

        Task {
            do {
                switch command {
                case "sessionDetail":
                    let detail = try await FitnessAPIClient.sessionDetail(id: sessionId)
                    let data = try Self.relayEncoder.encode(detail)
                    replyHandler(["ok": true, "detail": data])

                case "saveSessionStructure":
                    guard let data = message["request"] as? Data else {
                        replyHandler(["ok": false, "error": "missing_request"])
                        return
                    }
                    let request = try Self.relayDecoder.decode(FitnessSessionStructureRequest.self, from: data)
                    _ = try await FitnessAPIClient.saveSessionStructure(id: sessionId, request: request)
                    self.broadcastSessionChanged(sessionId)
                    self.onRemoteSessionChanged?(sessionId)
                    let detail = try await FitnessAPIClient.sessionDetail(id: sessionId)
                    let detailData = try Self.relayEncoder.encode(detail)
                    replyHandler(["ok": true, "detail": detailData])

                case "applySessionOperation":
                    guard let data = message["request"] as? Data else {
                        replyHandler(["ok": false, "error": "missing_request"])
                        return
                    }
                    let request = try Self.relayDecoder.decode(FitnessSessionOperationRequest.self, from: data)
                    let detail = try await FitnessAPIClient.applySessionOperation(id: sessionId, request: request)
                    self.broadcastSessionSnapshot(detail)
                    self.broadcastSessionChanged(sessionId)
                    self.onRemoteSessionChanged?(sessionId)
                    let detailData = try Self.relayEncoder.encode(detail)
                    replyHandler(["ok": true, "detail": detailData])

                case "completeSession":
                    let rpe = message["rpe"] as? Double
                    do {
                        _ = try await FitnessAPIClient.completeSession(id: sessionId, rpe: rpe)
                    } catch {
                        guard FitnessAPIClient.isMissingResourceError(error) else { throw error }
                    }
                    self.clearWorkoutIfCurrent(sessionId: sessionId)
                    self.onRemoteSessionCompleted?(sessionId)
                    replyHandler(["ok": true])

                case "discardSession":
                    do {
                        try await FitnessAPIClient.discardSession(id: sessionId)
                    } catch {
                        guard FitnessAPIClient.isMissingResourceError(error) else { throw error }
                    }
                    self.clearWorkoutIfCurrent(sessionId: sessionId)
                    replyHandler(["ok": true])

                default:
                    replyHandler(["ok": false, "error": "unknown_command"])
                }
            } catch {
                replyHandler(["ok": false, "error": String(describing: error)])
            }
        }
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        pushIfPossible()
        transferTimeEntry()
        handleRemoteWorkout(session.receivedApplicationContext)
    }

    /// The watch asks for the latest context (auth + workout) right after it
    /// activates, and may also push its own workout changes here.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["fitnessRelayCommand"] != nil {
            handleFitnessRelay(message, replyHandler: replyHandler)
            return
        }
        handleRemoteWorkout(message)
        replyHandler(mergedContext())
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleRemoteWorkout(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleRemoteWorkout(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleRemoteWorkout(userInfo)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
