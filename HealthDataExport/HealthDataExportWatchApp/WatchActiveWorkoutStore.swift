import Foundation
import Combine

/// The single source of truth for the watch's active workout. The root screen
/// presents the live workout whenever `current` is set. Local starts/ends are
/// broadcast to the phone; changes coming *from* the phone are applied without
/// re-broadcasting.
@MainActor
final class WatchActiveWorkoutStore: ObservableObject {
    static let shared = WatchActiveWorkoutStore()

    @Published var current: WatchSessionRef?

    /// Bumped when the phone reports a set change for the open session, so the
    /// active view reloads from the server.
    @Published private(set) var reloadTick = 0
    @Published private(set) var snapshotTick = 0
    private(set) var latestSnapshot: FitnessSessionDetail?

    /// The user started a workout on the watch.
    func startLocal(_ ref: WatchSessionRef) {
        current = ref
        WatchAuthSync.shared.broadcastWorkout(ref)
    }

    /// The workout finished on the watch.
    func endLocal() {
        guard current != nil else { return }
        current = nil
        WatchAuthSync.shared.broadcastWorkout(nil)
    }

    /// Apply a change that originated on the phone. No re-broadcast.
    func applyRemote(_ ref: WatchSessionRef?) {
        guard ref?.sessionId != current?.sessionId else { return }
        current = ref
    }

    /// The phone changed a set in the currently-open session — ask the view to reload.
    func noteRemoteChange(_ sessionId: Int) {
        guard sessionId == current?.sessionId else { return }
        reloadTick += 1
    }

    func noteRemoteSnapshot(_ sessionId: Int, detail: FitnessSessionDetail) {
        guard sessionId == current?.sessionId else { return }
        latestSnapshot = detail
        snapshotTick += 1
    }
}
