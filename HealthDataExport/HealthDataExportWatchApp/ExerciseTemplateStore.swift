import Foundation
import os

private let tplLog = Logger(subsystem: "HealthDataExportWatchApp", category: "exTemplate")

/// Persists one motion template per exercise (a 60×3 representative rep, built
/// from the user's own completed sets). Always overwritten with the most recent
/// set of that exercise, so the template tracks the user's current wrist
/// orientation / wearing and naturally counters cross-day drift.
///
/// Stored as a single JSON dict `[exerciseName: [[Double]]]` in Documents.
final class ExerciseTemplateStore {
    static let shared = ExerciseTemplateStore()

    private let lock = NSLock()
    private var cache: [String: [[Double]]]?

    private init() {}

    private static func fileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("ExerciseTemplates.json")
    }

    private func loadLocked() {
        guard cache == nil else { return }
        if let url = Self.fileURL(),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: [[Double]]].self, from: data) {
            cache = dict
        } else {
            cache = [:]
        }
    }

    func template(for exercise: String) -> [[Double]]? {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        return cache?[exercise]
    }

    func save(_ template: [[Double]], for exercise: String) {
        lock.lock()
        loadLocked()
        cache?[exercise] = template
        let snapshot = cache
        lock.unlock()
        guard let url = Self.fileURL(), let snapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        tplLog.info("saved template for \(exercise, privacy: .public)")
    }
}
