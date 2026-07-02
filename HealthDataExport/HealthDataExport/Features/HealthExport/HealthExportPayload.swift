import Foundation
import UIKit

struct HealthExportPayload {
    let configuration: ExportConfiguration
    let generatedAt: Date
    let startDate: Date
    let endDate: Date
    // raw metrics block — legacy path, kept as backup for the backend
    let metrics: [[String: Any]]
    // structured direct-ingest arrays — primary path, reliable storage
    let events: [[String: Any]]
    let heartRateSamples: [[String: Any]]
    let sleepSessions: [[String: Any]]
    let workouts: [[String: Any]]
    let stateOfMindEntries: [[String: Any]]
    let customDictionary: [String: Any]?

    init(
        configuration: ExportConfiguration,
        generatedAt: Date,
        startDate: Date,
        endDate: Date,
        metrics: [[String: Any]],
        events: [[String: Any]] = [],
        heartRateSamples: [[String: Any]] = [],
        sleepSessions: [[String: Any]] = [],
        workouts: [[String: Any]] = [],
        stateOfMindEntries: [[String: Any]] = [],
        customDictionary: [String: Any]? = nil
    ) {
        self.configuration = configuration
        self.generatedAt = generatedAt
        self.startDate = startDate
        self.endDate = endDate
        self.metrics = metrics
        self.events = events
        self.heartRateSamples = heartRateSamples
        self.sleepSessions = sleepSessions
        self.workouts = workouts
        self.stateOfMindEntries = stateOfMindEntries
        self.customDictionary = customDictionary
    }

    // Stable per configuration + calendar day — enables upsert on the backend.
    var syncId: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dayStr = formatter.string(from: Calendar.current.startOfDay(for: startDate))
        let prefix = configuration.id.uuidString.lowercased().prefix(8)
        return "\(prefix)_\(dayStr)"
    }

    var dictionary: [String: Any] {
        if let customDictionary { return customDictionary }

        var dict: [String: Any] = [
            "schema_version": "health-data-export.v2",
            "sync_id": syncId,
            "sent_at": generatedAt.iso8601String,
            "generated_at": generatedAt.iso8601String,
            "source": "apple_health_export_app",
            "timezone_name": TimeZone.current.identifier,
            "timezone_offset_minutes": TimeZone.current.secondsFromGMT() / 60,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "device": [
                "platform": "ios",
                "device_name": UIDevice.current.name
            ],
            "configuration": [
                "id": configuration.id.uuidString,
                "name": configuration.name
            ],
            "period": [
                "start": startDate.iso8601String,
                "end": endDate.iso8601String,
                "lookback_hours": configuration.lookbackHours
            ]
        ]

        // Direct structured arrays — primary ingest path.
        let hasStructured = !events.isEmpty || !heartRateSamples.isEmpty || !sleepSessions.isEmpty
            || !workouts.isEmpty || !stateOfMindEntries.isEmpty
        if !events.isEmpty { dict["events"] = events }
        if !heartRateSamples.isEmpty { dict["heartRateSamples"] = heartRateSamples }
        if !sleepSessions.isEmpty { dict["sleepSessions"] = sleepSessions }
        if !workouts.isEmpty { dict["workouts"] = workouts }
        if !stateOfMindEntries.isEmpty { dict["stateOfMindEntries"] = stateOfMindEntries }

        // Only include raw metrics block when no structured arrays exist.
        // Sending both causes the backend to merge duplicate entries into the same
        // normalized list; within a single transaction Hibernate doesn't flush
        // between the existsByDedupeKey checks, so both pass and the commit hits
        // the unique constraint → DataIntegrityViolationException → HTTP 500.
        if !hasStructured && !metrics.isEmpty { dict["metrics"] = metrics }

        return dict
    }

    var itemCount: Int {
        let structured = events.count + heartRateSamples.count + sleepSessions.count
            + workouts.count + stateOfMindEntries.count
        return structured > 0 ? structured : metrics.count
    }

    var jsonData: Data {
        get throws {
            try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        }
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter.exportFormatter.string(from: self)
    }
}

extension ISO8601DateFormatter {
    static let exportFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
