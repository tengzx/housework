import Foundation

struct HealthExportPayload {
    let configuration: ExportConfiguration
    let generatedAt: Date
    let startDate: Date
    let endDate: Date
    let metrics: [[String: Any]]
    let customDictionary: [String: Any]?

    init(
        configuration: ExportConfiguration,
        generatedAt: Date,
        startDate: Date,
        endDate: Date,
        metrics: [[String: Any]],
        customDictionary: [String: Any]? = nil
    ) {
        self.configuration = configuration
        self.generatedAt = generatedAt
        self.startDate = startDate
        self.endDate = endDate
        self.metrics = metrics
        self.customDictionary = customDictionary
    }

    var dictionary: [String: Any] {
        if let customDictionary {
            return customDictionary
        }

        return [
            "schema_version": "health-data-export.v1",
            "export_id": UUID().uuidString,
            "generated_at": generatedAt.iso8601String,
            "source": [
                "app": "HealthDataExport",
                "platform": "apple-health"
            ],
            "configuration": [
                "id": configuration.id.uuidString,
                "name": configuration.name
            ],
            "period": [
                "start": startDate.iso8601String,
                "end": endDate.iso8601String,
                "lookback_hours": configuration.lookbackHours
            ],
            "metrics": metrics
        ]
    }

    var itemCount: Int {
        return metrics.count
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
