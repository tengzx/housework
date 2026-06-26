import Foundation

struct ExportConfiguration: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var endpointURL: String
    var bearerToken: String
    var lookbackHours: Int
    var selectedMetricIDs: Set<HealthMetric.ID>
    var includeSamples: Bool
    var lastSentAt: Date?
    var lastStatus: String?

    init(
        id: UUID = UUID(),
        name: String = "Life Energy V3",
        endpointURL: String = "",
        bearerToken: String = "",
        lookbackHours: Int = 24,
        selectedMetricIDs: Set<HealthMetric.ID> = Set(HealthMetric.allCases.filter { $0.priority != .subjective }.map(\.id)),
        includeSamples: Bool = false,
        lastSentAt: Date? = nil,
        lastStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.bearerToken = bearerToken
        self.lookbackHours = lookbackHours
        self.selectedMetricIDs = selectedMetricIDs
        self.includeSamples = includeSamples
        self.lastSentAt = lastSentAt
        self.lastStatus = lastStatus
    }

    var selectedMetrics: [HealthMetric] {
        HealthMetric.allCases.filter { selectedMetricIDs.contains($0.id) }
    }

    var isReadyToSend: Bool {
        URL(string: endpointURL)?.scheme?.hasPrefix("http") == true && !selectedMetricIDs.isEmpty
    }

    var isReadyToPreview: Bool {
        !selectedMetricIDs.isEmpty
    }
}
