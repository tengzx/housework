import Foundation
import Combine
import WatchConnectivity

/// Receives the bearer token pushed from the paired iPhone and keeps
/// `AuthTokenStore` in sync so the watch's own API calls are authenticated.
///
/// The token is cached in `UserDefaults` so a cold watch launch (before the phone
/// has a chance to push again) can still make authenticated calls. iOS remains the
/// source of truth: a logout on the phone clears the token here too.
@MainActor
final class WatchAuthSync: NSObject, ObservableObject {
    static let shared = WatchAuthSync()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var nickname = ""

    private let tokenKey = "watch.auth.token"
    private let nicknameKey = "watch.auth.nickname"

    // Shared active-session state (see PhoneWatchSync for the versioning scheme).
    private var wkVersion: Double = 0
    private var wkSession: WatchSessionRef?

    // In-session change pings.
    private var wkChangeStamp: Double = 0
    private var wkChangedSession: Int?
    private var lastSeenChangeStamp: Double = 0
    private var wkSnapshotStamp: Double = 0
    private var wkSnapshotSession: Int?
    private var wkSnapshotData: Data?
    private var lastSeenSnapshotStamp: Double = 0
    private var wkHeartRate: Int?
    private var wkHeartRateSession: Int?

    // Active time-tracking entry sync (both directions).
    private var lastSeenTeStamp: Double = 0   // newest entry received from the phone
    private var teStamp: Double = 0           // version of our own broadcasts
    private var teData: Data?

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

    override init() {
        super.init()
        let savedToken = UserDefaults.standard.string(forKey: tokenKey)
        let savedNick = UserDefaults.standard.string(forKey: nicknameKey) ?? ""
        applyToken(savedToken, nickname: savedNick)
        // When the watch changes its own active time entry, relay it to the phone.
        SharedActivityStore.onWrite = { activity in
            Task { @MainActor in WatchAuthSync.shared.broadcastTimeEntry(activity) }
        }
    }

    /// Activate the session and pull the latest context. Call once at launch.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handleContext(_ context: [String: Any]) {
        // Auth: an empty/absent token means the phone is logged out.
        if context["authToken"] != nil || context["nickname"] != nil {
            let token = (context["authToken"] as? String)?.trimmingCharacters(in: .whitespaces)
            let nick = context["nickname"] as? String ?? nickname
            UserDefaults.standard.set(token, forKey: tokenKey)
            UserDefaults.standard.set(nick, forKey: nicknameKey)
            applyToken(token, nickname: nick)
        }
        // Active workout session pushed from the phone.
        handleRemoteWorkout(context)
        // Active time-tracking entry pushed from the phone → face complication.
        handleRemoteTimeEntry(context)
    }

    /// Mirror the phone's active time-tracking entry into the App Group so the
    /// watch-face complication shows the latest, even when the change happened on
    /// the phone. Versioned so an older context can't overwrite a newer one.
    private func handleRemoteTimeEntry(_ dict: [String: Any]) {
        guard let stamp = dict["teStamp"] as? Double, stamp > lastSeenTeStamp else { return }
        lastSeenTeStamp = stamp
        let data = dict["teData"] as? Data
        if stamp > teStamp {
            teStamp = stamp
            teData = data
        }
        let activity = data.flatMap {
            try? Self.relayDecoder.decode(SharedActiveActivity.self, from: $0)
        }
        // This change came *from* the phone, so update the local time-tracker
        // model silently instead of relaying it straight back.
        ShortcutRecordStore.shared.applyRemoteActive(activity)
    }

    /// The watch changed its own active time-tracking entry — relay it to the phone.
    /// Versioned so the newest change wins.
    func broadcastTimeEntry(_ activity: SharedActiveActivity?) {
        teStamp = max(teStamp + 0.001, Date().timeIntervalSince1970)
        teData = activity.flatMap { try? Self.relayEncoder.encode($0) }
        pushWorkoutContext()
        transferTimeEntry()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(workoutMessage(), replyHandler: nil, errorHandler: nil)
        }
    }

    private func applyToken(_ token: String?, nickname: String) {
        let normalized = (token?.isEmpty == false) ? token : nil
        AuthTokenStore.set(normalized)
        self.nickname = nickname
        self.isAuthenticated = normalized != nil
    }

    // MARK: - Workout session sync

    /// Broadcast a local active-session change to the phone (nil = ended).
    func broadcastWorkout(_ ref: WatchSessionRef?) {
        wkVersion = max(wkVersion + 0.001, Date().timeIntervalSince1970)
        wkSession = ref
        pushWorkoutContext()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(workoutMessage(), replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleRemoteWorkout(_ dict: [String: Any]) {
        if let version = dict["wkVersion"] as? Double, version > wkVersion {
            wkVersion = version
            let ref = (dict["wkSessionId"] as? Int).map {
                WatchSessionRef(sessionId: $0, name: dict["wkName"] as? String ?? "")
            }
            wkSession = ref
            WatchActiveWorkoutStore.shared.applyRemote(ref)
        }
        handleRemoteChange(dict)
        handleRemoteSnapshot(dict)
    }

    /// Broadcast that a session's sets changed so the phone reloads it.
    func broadcastSessionChanged(_ sessionId: Int) {
        wkChangeStamp = max(wkChangeStamp + 0.001, Date().timeIntervalSince1970)
        wkChangedSession = sessionId
        pushWorkoutContext()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(workoutMessage(), replyHandler: nil, errorHandler: nil)
        }
    }

    func broadcastSessionSnapshot(_ detail: FitnessSessionDetail) {
        guard let data = try? Self.relayEncoder.encode(detail) else { return }
        wkSnapshotStamp = max(wkSnapshotStamp + 0.001, Date().timeIntervalSince1970)
        wkSnapshotSession = detail.id
        wkSnapshotData = data
        pushWorkoutContext()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(workoutMessage(), replyHandler: nil, errorHandler: nil)
        }
    }

    /// Push the live heart rate to the phone so its floating workout bar can show
    /// it. Sent only when reachable — HR is live data, stale values aren't useful.
    func broadcastHeartRate(_ bpm: Int, sessionId: Int) {
        wkHeartRate = bpm
        wkHeartRateSession = sessionId
        pushWorkoutContext()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(workoutMessage(), replyHandler: nil, errorHandler: nil)
    }

    func phoneSessionDetail(id: Int) async throws -> FitnessSessionDetail {
        let reply = try await sendFitnessRelay(["fitnessRelayCommand": "sessionDetail", "sessionId": id])
        guard let data = reply["detail"] as? Data else { throw WatchPhoneRelayError.badReply }
        return try Self.relayDecoder.decode(FitnessSessionDetail.self, from: data)
    }

    func phoneSaveSessionStructure(id: Int, request: FitnessSessionStructureRequest) async throws -> FitnessSessionDetail {
        let data = try Self.relayEncoder.encode(request)
        let reply = try await sendFitnessRelay([
            "fitnessRelayCommand": "saveSessionStructure",
            "sessionId": id,
            "request": data
        ])
        guard let detailData = reply["detail"] as? Data else { throw WatchPhoneRelayError.badReply }
        return try Self.relayDecoder.decode(FitnessSessionDetail.self, from: detailData)
    }

    func phoneApplySessionOperation(id: Int, request: FitnessSessionOperationRequest) async throws -> FitnessSessionDetail {
        let data = try Self.relayEncoder.encode(request)
        let reply = try await sendFitnessRelay([
            "fitnessRelayCommand": "applySessionOperation",
            "sessionId": id,
            "request": data
        ])
        guard let detailData = reply["detail"] as? Data else { throw WatchPhoneRelayError.badReply }
        return try Self.relayDecoder.decode(FitnessSessionDetail.self, from: detailData)
    }

    func phoneCompleteSession(id: Int, rpe: Double?) async throws {
        var message: [String: Any] = ["fitnessRelayCommand": "completeSession", "sessionId": id]
        if let rpe { message["rpe"] = rpe }
        _ = try await sendFitnessRelay(message)
    }

    func phoneDiscardSession(id: Int) async throws {
        _ = try await sendFitnessRelay(["fitnessRelayCommand": "discardSession", "sessionId": id])
    }

    private func sendFitnessRelay(_ message: [String: Any]) async throws -> [String: Any] {
        guard WCSession.isSupported() else { throw WatchPhoneRelayError.unavailable }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            throw WatchPhoneRelayError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                if (reply["ok"] as? Bool) == true {
                    continuation.resume(returning: reply)
                } else {
                    continuation.resume(throwing: WatchPhoneRelayError.remote(reply["error"] as? String ?? "unknown"))
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    private func handleRemoteChange(_ dict: [String: Any]) {
        guard let stamp = dict["wkChangeStamp"] as? Double,
              let sessionId = dict["wkChangedSession"] as? Int,
              stamp > lastSeenChangeStamp else { return }
        lastSeenChangeStamp = stamp
        WatchActiveWorkoutStore.shared.noteRemoteChange(sessionId)
    }

    private func handleRemoteSnapshot(_ dict: [String: Any]) {
        guard let stamp = dict["wkSnapshotStamp"] as? Double,
              let sessionId = dict["wkSnapshotSession"] as? Int,
              let data = dict["wkSnapshotDetail"] as? Data,
              stamp > lastSeenSnapshotStamp else { return }
        lastSeenSnapshotStamp = stamp
        guard let detail = try? Self.relayDecoder.decode(FitnessSessionDetail.self, from: data) else { return }
        WatchActiveWorkoutStore.shared.noteRemoteSnapshot(sessionId, detail: detail)
    }

    private func workoutMessage() -> [String: Any] {
        var msg: [String: Any] = ["wkVersion": wkVersion]
        if let session = wkSession {
            msg["wkSessionId"] = session.sessionId
            msg["wkName"] = session.name
        }
        if wkChangeStamp > 0, let changed = wkChangedSession {
            msg["wkChangeStamp"] = wkChangeStamp
            msg["wkChangedSession"] = changed
        }
        if wkSnapshotStamp > 0, let sessionId = wkSnapshotSession, let data = wkSnapshotData {
            msg["wkSnapshotStamp"] = wkSnapshotStamp
            msg["wkSnapshotSession"] = sessionId
            msg["wkSnapshotDetail"] = data
        }
        if let bpm = wkHeartRate, let sessionId = wkHeartRateSession {
            msg["wkHeartRate"] = bpm
            msg["wkHrSession"] = sessionId
        }
        if teStamp > 0 {
            msg["teStamp"] = teStamp
            if let data = teData { msg["teData"] = data }
        }
        return msg
    }

    private func pushWorkoutContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var ctx = workoutMessage()
        ctx["updatedAt"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(ctx)
    }

    private func transferTimeEntry() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let msg = workoutMessage()
        guard msg["teStamp"] != nil else { return }
        session.transferUserInfo(msg)
    }
}

private enum WatchPhoneRelayError: Error {
    case unavailable
    case badReply
    case remote(String)
}

extension WatchAuthSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Adopt whatever the phone last delivered while we were away…
        let cached = session.receivedApplicationContext
        let reachable = activationState == .activated && session.isReachable
        Task { @MainActor in
            if !cached.isEmpty { self.handleContext(cached) }
        }
        // …and actively ask for the freshest token if the phone is reachable.
        guard reachable else { return }
        session.sendMessage([:], replyHandler: { reply in
            Task { @MainActor in self.handleContext(reply) }
        }, errorHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.handleContext(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let sessionId = message["deleteWorkoutSession"] as? Int {
            Task { await WatchWorkoutManager.deleteWorkout(sessionId: sessionId) }
            return
        }
        Task { @MainActor in self.handleContext(message) }
    }

    /// The phone queues a workout-deletion request here (via `transferUserInfo`)
    /// so it's delivered even when the watch app isn't reachable at delete time.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let sessionId = userInfo["deleteWorkoutSession"] as? Int {
            Task { await WatchWorkoutManager.deleteWorkout(sessionId: sessionId) }
            return
        }
        Task { @MainActor in self.handleContext(userInfo) }
    }
}
