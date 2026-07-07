import Foundation
import Combine
import os

private let onsetLog = Logger(subsystem: "HealthDataExportWatchApp", category: "setOnset")

/// What the detector proposes: "you seem to have started <exercise> set N".
struct OnsetSuggestion: Equatable {
    let setId: Int
    let exerciseName: String
    let setIndex: Int      // 0-based within its exercise
    let setCount: Int
}

/// Decides, from wrist motion, when a *pending* set has begun. On a match the
/// view auto-starts the set (haptic + a transient "已开始 · 撤销" undo banner) —
/// no confirm tap; the undo is the safety net for the rare false positive.
///
/// v2 — DTW template matching (ExerSense-inspired, validated offline on real
/// gym data: threshold 0.20 → 9/10 sets detected, 0/10 rest-period false
/// positives, vs v1 rhythm-only which false-fired throughout rest). It does NOT
/// own a sensor: `WorkoutSessionRecorder` feeds every acceleration sample here.
///
/// When armed for a pending set, it loads that exercise's personal template
/// (`ExerciseTemplateStore`, auto-built from the user's own completed sets). It
/// segments the trailing motion into reps and fires when `minMatches`
/// consecutive reps match the template within `threshold`. No template yet
/// (exercise never completed before) → it stays silent rather than guess.
final class SetOnsetDetector: ObservableObject {
    static let shared = SetOnsetDetector()

    /// Non-nil when the detector wants to propose starting a set.
    @MainActor @Published private(set) var suggestion: OnsetSuggestion?

    private static let windowS = 8.0        // trailing buffer (holds several reps)
    private static let stepS = 0.5          // re-evaluate cadence
    private static let minMatches = 1       // on-template reps to fire (was 2; lowered to fire ~rep 2, not 3–4)
    private static let threshold = 0.20     // max DTW distance for a match
    private static let cooldownS = 15.0
    /// Absolute motion floor (peak smoothed accel-norm energy, g²). Below this
    /// the wrist is effectively still (e.g. leg press) → never fire, regardless
    /// of template. Measured margin: real wrist reps peak ≥ 0.85, still ≤ ~0.10.
    private static let motionFloor = 0.20

    private let lock = NSLock()
    private var armed: OnsetSuggestion?
    private var template: [[Double]]?       // 60×3, nil = don't fire
    private var suggesting = false
    private var buf: [[Double]] = []        // rows [t, ax, ay, az]
    private var lastEvalT: Double = 0
    private var snoozeUntilEpoch: Double = 0
    private var currentActivity = "unknown"

    private init() {}

    // MARK: - Arm / disarm (main thread)

    func arm(_ target: OnsetSuggestion) {
        let tpl = ExerciseTemplateStore.shared.template(for: target.exerciseName)
        lock.lock()
        armed = target
        template = tpl
        suggesting = false
        buf.removeAll(keepingCapacity: true)
        lastEvalT = 0
        lock.unlock()
        Task { @MainActor in
            if self.suggestion?.setId != target.setId { self.suggestion = nil }
        }
        onsetLog.info("armed set=\(target.setId, privacy: .public) \(target.exerciseName, privacy: .public) template=\(tpl != nil, privacy: .public)")
    }

    func disarm() {
        lock.lock()
        armed = nil
        template = nil
        suggesting = false
        buf.removeAll(keepingCapacity: false)
        lock.unlock()
        Task { @MainActor in self.suggestion = nil }
    }

    /// User ignored a suggestion: clear it and hush for a cooldown, keep watching.
    func dismissSuggestion() {
        lock.lock()
        snoozeUntilEpoch = Date().timeIntervalSince1970 + Self.cooldownS
        suggesting = false
        buf.removeAll(keepingCapacity: true)
        lastEvalT = 0
        lock.unlock()
        Task { @MainActor in self.suggestion = nil }
    }

    func setActivity(_ label: String) {
        lock.lock(); currentActivity = label; lock.unlock()
    }

    /// Called after a set completes and its template is (re)built. Closes the
    /// race where a pending next set armed before this session's fresh template
    /// existed and loaded a stale/nil one — hot-swap it in.
    func refreshTemplate(for exercise: String) {
        let tpl = ExerciseTemplateStore.shared.template(for: exercise)
        lock.lock()
        if armed?.exerciseName == exercise, !suggesting { template = tpl }
        lock.unlock()
    }

    // MARK: - Feed (recorder's motion thread)

    /// One acceleration sample (gravity-removed user acceleration). `t` is
    /// monotonic device-uptime seconds.
    func feed(t: Double, ax: Double, ay: Double, az: Double) {
        var fireTarget: OnsetSuggestion?
        lock.lock()
        if let target = armed, let tpl = template, !suggesting {
            buf.append([t, ax, ay, az])
            let cutoff = t - Self.windowS
            var drop = 0
            while drop < buf.count && buf[drop][0] < cutoff { drop += 1 }
            if drop > 0 { buf.removeFirst(drop) }

            if t - lastEvalT >= Self.stepS {
                lastEvalT = t
                let vetoed = currentActivity == "walking" || currentActivity == "running"
                let snoozed = Date().timeIntervalSince1970 < snoozeUntilEpoch
                if !vetoed && !snoozed && matchesTemplate(tpl) {
                    suggesting = true
                    fireTarget = target
                }
            }
        }
        lock.unlock()

        if let target = fireTarget {
            onsetLog.info("suggest start set=\(target.setId, privacy: .public)")
            Task { @MainActor in
                self.suggestion = target
                Haptics.notify(success: true)
            }
        }
    }

    /// True if the last `minMatches` complete reps in the buffer all match the
    /// template within threshold. Caller holds `lock`.
    private func matchesTemplate(_ tpl: [[Double]]) -> Bool {
        // Gate: if the wrist is essentially still, there's nothing to match —
        // don't let a low-amplitude "still" template match low-amplitude rest.
        guard RepMotionMath.peakSmoothedEnergy(buf) >= Self.motionFloor else { return false }
        let segs = RepMotionMath.segments(buf)
        guard segs.count >= Self.minMatches else { return false }
        for seg in segs.suffix(Self.minMatches) {
            let rs = RepMotionMath.resample(seg)
            if rs.isEmpty || RepMotionMath.dtw(tpl, rs) > Self.threshold { return false }
        }
        return true
    }
}
