import Foundation
import Combine
import CoreMotion
import os

private let sessionRecLog = Logger(subsystem: "HealthDataExportWatchApp", category: "sessionRec")

/// Records one whole workout continuously — every set AND the gaps between them
/// (rest, walking, fidgeting) — to build labelled training data for the onset
/// detector, and is the single owner of the motion sensors for the workout
/// (Apple: one CMMotionManager per app). It feeds each sample to
/// `SetOnsetDetector` for live detection and persists everything to disk:
///
///   Documents/WorkoutCaptures/<sessionId>_<startEpoch>/
///     motion.ndjson   — newline-delimited batches of [t,ax,ay,az,rx,ry,rz,gx,gy,gz]
///     events.json     — meta + timeline (set start/complete, suggestions,
///                       confirm/ignore, heart-rate readings)
///
/// Continuous capture is near-free on battery here: the sensors already run the
/// whole workout (this recorder during sets, the detector between them) — we're
/// just also *saving* the between-set stream. The real cost is storage, capped
/// by keeping only the most recent `keepSessions` directories.
///
/// Nothing is uploaded; all local.
final class WorkoutSessionRecorder: ObservableObject {
    static let shared = WorkoutSessionRecorder()

    /// On-device debug readout, shown on the controls page.
    @MainActor @Published private(set) var debugStatus = "采集: 待机"

    private let manager = CMMotionManager()
    /// Motion delivers here; all mutable state and file I/O below are confined to it.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "WorkoutSessionRecorder"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private static let sampleRateHz: Double = 100
    private static let batchSize = 100          // ~1s of samples per NDJSON line
    private static let keepSessions = 20        // storage cap: most recent N workouts

    /// A timeline entry. Types: setStart / setComplete / suggest / confirm /
    /// ignore / hr. `t` is seconds since session start (wall clock).
    private struct Event: Codable {
        let t: Double
        let type: String
        var setId: Int?
        var exercise: String?
        var setIndex: Int?
        var reps: Int?
        var weightKg: Double?
        var bpm: Int?
        var activity: String?
    }

    /// An explicit, human-readable partition of the whole session into labelled
    /// intervals, computed at end from the event timeline. `kind` is "set"
    /// (real exercise, setStart→setComplete) or "gap" (rest/walk between sets).
    /// Times are seconds since session start.
    private struct Segment: Codable {
        let start: Double
        let end: Double
        let kind: String
        var setId: Int?
        var exercise: String?
        var activities: [String]?   // activity labels observed during a gap
    }

    private struct Meta: Codable {
        let sessionId: Int
        let startEpoch: Double          // Date at start()
        var firstSampleEpoch: Double    // Date at first motion sample (aligns motion t to events)
        let sampleRateHz: Double
        var events: [Event]
        var segments: [Segment] = []    // filled in at endSession
    }

    // Confined to `queue`.
    private var running = false
    private var dir: URL?
    private var handle: FileHandle?
    private var meta: Meta?
    private var firstTimestamp: TimeInterval?
    private var startEpoch: Double = 0
    private var batch: [[Double]] = []
    private var totalSamples = 0
    private var lastMetaWriteEpoch: Double = 0
    // Per-set motion buffer for auto-building the exercise's DTW template.
    private var setActiveExercise: String?
    private var setBuffer: [[Double]] = []   // rows [t, ax, ay, az]

    private init() {}

    // MARK: - Lifecycle

    /// Master switch for the sensor + live onset-detection pipeline. Must be ON
    /// for the auto-start feature to work at all (the detector has no sensor of
    /// its own — this recorder feeds it).
    static var captureEnabled = true

    /// Whether to also persist the raw motion/event stream to disk
    /// (`WorkoutCaptures/…`). This is ONLY needed for offline analysis /
    /// exporting `.xcappdata` — the live feature does not read it back. Kept OFF
    /// in shipping: it removes the ~7MB/workout footprint and the disk-I/O that
    /// was the suspected post-workout crash. Flip ON only to gather debug data.
    static var persistToDisk = false

    func startSession(sessionId: Int) {
        guard Self.captureEnabled else {
            report("采集已关闭(诊断)")
            return
        }
        guard manager.isDeviceMotionAvailable else {
            report("运动不可用")
            return
        }
        let start = Date().timeIntervalSince1970
        queue.addOperation { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.startEpoch = start
            self.firstTimestamp = nil
            self.totalSamples = 0
            self.lastMetaWriteEpoch = 0
            self.batch.removeAll(keepingCapacity: true)
            if Self.persistToDisk {
                self.openFiles(sessionId: sessionId, startEpoch: start)
                self.writeMetaLocked()   // ensure events.json exists from the start
                Self.cleanupOldSessions()
            }
        }

        startSensors()
        report("录制中")
        sessionRecLog.info("session capture started id=\(sessionId, privacy: .public)")
    }

    private func startSensors() {
        manager.stopDeviceMotionUpdates()   // idempotent: never double-start
        manager.deviceMotionUpdateInterval = 1.0 / Self.sampleRateHz
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.onMotion(motion)
        }
    }

    /// Stop and flush. `save == false` discards the whole session directory.
    func endSession(save: Bool = true) {
        manager.stopDeviceMotionUpdates()
        queue.addOperation { [weak self] in
            guard let self, self.running else { return }
            self.running = false
            if self.handle != nil || self.meta != nil {
                self.flushBatchLocked()
                self.meta?.segments = self.buildSegmentsLocked(end: Date().timeIntervalSince1970 - self.startEpoch)
                self.writeMetaLocked()
                try? self.handle?.close()
                self.handle = nil
                if !save, let dir = self.dir {
                    try? FileManager.default.removeItem(at: dir)
                }
                self.dir = nil
                self.meta = nil
            }
            self.setActiveExercise = nil
            self.setBuffer.removeAll(keepingCapacity: false)
        }
        report("待机")
    }

    // MARK: - Event logging (any thread)

    func logSetStart(setId: Int, exercise: String, setIndex: Int) {
        appendEvent(type: "setStart") { $0.setId = setId; $0.exercise = exercise; $0.setIndex = setIndex }
        queue.addOperation { [weak self] in
            self?.setActiveExercise = exercise
            self?.setBuffer.removeAll(keepingCapacity: true)
        }
    }
    func logSetComplete(setId: Int, reps: Int?, weightKg: Double?) {
        appendEvent(type: "setComplete") { $0.setId = setId; $0.reps = reps; $0.weightKg = weightKg }
        queue.addOperation { [weak self] in
            guard let self, let ex = self.setActiveExercise else { return }
            // Build/refresh this exercise's template from the set just finished.
            if let tpl = RepMotionMath.representativeTemplate(from: self.setBuffer) {
                ExerciseTemplateStore.shared.save(tpl, for: ex)
                SetOnsetDetector.shared.refreshTemplate(for: ex)   // hot-swap into a pending arm
            }
            self.setActiveExercise = nil
            self.setBuffer.removeAll(keepingCapacity: false)
        }
    }
    func logSuggest(setId: Int) { appendEvent(type: "suggest") { $0.setId = setId } }
    func logConfirm(setId: Int) { appendEvent(type: "confirm") { $0.setId = setId } }
    func logIgnore(setId: Int) { appendEvent(type: "ignore") { $0.setId = setId } }
    func logHeartRate(_ bpm: Int) { appendEvent(type: "hr") { $0.bpm = bpm } }

    private func appendEvent(type: String, build: @escaping (inout Event) -> Void) {
        let epoch = Date().timeIntervalSince1970
        queue.addOperation { [weak self] in
            guard let self, self.running, self.meta != nil else { return }
            var e = Event(t: epoch - self.startEpoch, type: type)
            build(&e)
            self.meta?.events.append(e)
            // Persist at most every ~10s (plus set events, which are rare and
            // worth keeping promptly). Rewriting the whole file on every HR tick
            // was O(n²) I/O over a long workout.
            let important = type == "setStart" || type == "setComplete" || type == "confirm"
            if important || epoch - self.lastMetaWriteEpoch >= 10 {
                self.lastMetaWriteEpoch = epoch
                self.writeMetaLocked()
            }
        }
    }

    // MARK: - Motion (queue)

    private func onMotion(_ motion: CMDeviceMotion) {
        guard running else { return }
        if firstTimestamp == nil {
            firstTimestamp = motion.timestamp
            meta?.firstSampleEpoch = Date().timeIntervalSince1970
        }
        let t = motion.timestamp - (firstTimestamp ?? motion.timestamp)
        let ua = motion.userAcceleration, rr = motion.rotationRate, g = motion.gravity
        totalSamples += 1

        // Live onset detection (DTW template matching) is fed acceleration.
        SetOnsetDetector.shared.feed(t: motion.timestamp, ax: ua.x, ay: ua.y, az: ua.z)

        // While a set is running, buffer its motion so we can build/refresh that
        // exercise's template when the set completes.
        if setActiveExercise != nil {
            setBuffer.append([motion.timestamp, ua.x, ua.y, ua.z])
        }

        // Raw stream to disk only when explicitly gathering debug data.
        if Self.persistToDisk {
            batch.append([t, ua.x, ua.y, ua.z, rr.x, rr.y, rr.z, g.x, g.y, g.z])
            if batch.count >= Self.batchSize { flushBatchLocked() }
        }

        // Live sample count = proof capture is alive (shown on controls page).
        if totalSamples % Self.batchSize == 0 { report("录制中 \(totalSamples)") }
    }

    // MARK: - Persistence (queue)

    private func openFiles(sessionId: Int, startEpoch: Double) {
        guard let base = Self.capturesDirectory() else { return }
        let dir = base.appendingPathComponent("\(sessionId)_\(Int(startEpoch))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let motionURL = dir.appendingPathComponent("motion.ndjson")
        FileManager.default.createFile(atPath: motionURL.path, contents: nil)
        self.dir = dir
        self.handle = try? FileHandle(forWritingTo: motionURL)
        self.meta = Meta(sessionId: sessionId, startEpoch: startEpoch, firstSampleEpoch: startEpoch,
                         sampleRateHz: Self.sampleRateHz, events: [])
    }

    private func flushBatchLocked() {
        guard !batch.isEmpty, let handle else { batch.removeAll(keepingCapacity: true); return }
        if let data = try? JSONSerialization.data(withJSONObject: batch) {
            try? handle.write(contentsOf: data)
            try? handle.write(contentsOf: Data([0x0a]))   // newline
        }
        batch.removeAll(keepingCapacity: true)
    }

    /// Partition the session into "set" and "gap" segments from the event
    /// timeline. Must run on `queue`.
    private func buildSegmentsLocked(end: Double) -> [Segment] {
        guard let meta else { return [] }
        let starts = meta.events.filter { $0.type == "setStart" }
        let completes = meta.events.filter { $0.type == "setComplete" }
        let acts = meta.events.filter { $0.type == "activity" }

        // Pair each start with its earliest matching complete (or session end).
        var intervals: [(s: Double, e: Double, setId: Int?, ex: String?)] = []
        for st in starts {
            let comp = completes
                .filter { $0.setId == st.setId && $0.t >= st.t }
                .min { $0.t < $1.t }
            intervals.append((st.t, comp?.t ?? end, st.setId, st.exercise))
        }
        intervals.sort { $0.s < $1.s }

        func activitiesIn(_ a: Double, _ b: Double) -> [String] {
            Array(Set(acts.filter { $0.t >= a && $0.t < b }.compactMap { $0.activity })).sorted()
        }

        var segs: [Segment] = []
        var cursor = 0.0
        for iv in intervals {
            if iv.s > cursor + 0.5 {
                segs.append(Segment(start: cursor, end: iv.s, kind: "gap",
                                    setId: nil, exercise: nil, activities: activitiesIn(cursor, iv.s)))
            }
            segs.append(Segment(start: iv.s, end: iv.e, kind: "set",
                                setId: iv.setId, exercise: iv.ex, activities: nil))
            cursor = max(cursor, iv.e)
        }
        if end > cursor + 0.5 {
            segs.append(Segment(start: cursor, end: end, kind: "gap",
                                setId: nil, exercise: nil, activities: activitiesIn(cursor, end)))
        }
        return segs
    }

    private func writeMetaLocked() {
        guard let dir, let meta else { return }
        let url = dir.appendingPathComponent("events.json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func capturesDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("WorkoutCaptures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Keep only the most recent `keepSessions` capture directories.
    private static func cleanupOldSessions() {
        guard let base = capturesDirectory() else { return }
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        let sorted = dirs.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return da > db
        }
        for old in sorted.dropFirst(keepSessions) {
            try? fm.removeItem(at: old)
        }
    }

    private func report(_ text: String) {
        Task { @MainActor in self.debugStatus = "采集: \(text)" }
    }
}
