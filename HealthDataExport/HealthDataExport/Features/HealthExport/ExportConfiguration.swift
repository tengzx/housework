import Foundation

struct ExportConfiguration: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var endpointURL: String
    /// Runtime-only credential. Loaded from Keychain by `ConfigurationStore`.
    /// Legacy `UserDefaults` values are decoded for one-time migration, but new
    /// saves intentionally do not encode this field.
    var bearerToken: String
    var lookbackHours: Int
    var selectedMetricIDs: Set<HealthMetric.ID>
    var includeSamples: Bool
    var lastSentAt: Date?
    var lastStatus: String?

    init(
        id: UUID = UUID(),
        name: String = "Life Energy V3",
        endpointURL: String = AppEnvironment.defaultHealthIngestURL,
        bearerToken: String = "",
        lookbackHours: Int = 24,
        selectedMetricIDs: Set<HealthMetric.ID> = Set(HealthMetric.allCases.filter { $0.priority != .subjective }.map(\.id)),
        includeSamples: Bool = true,
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpointURL
        case bearerToken
        case lookbackHours
        case selectedMetricIDs
        case includeSamples
        case lastSentAt
        case lastStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpointURL = try container.decode(String.self, forKey: .endpointURL)
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        lookbackHours = try container.decode(Int.self, forKey: .lookbackHours)
        selectedMetricIDs = try container.decode(Set<HealthMetric.ID>.self, forKey: .selectedMetricIDs)
        includeSamples = try container.decode(Bool.self, forKey: .includeSamples)
        lastSentAt = try container.decodeIfPresent(Date.self, forKey: .lastSentAt)
        lastStatus = try container.decodeIfPresent(String.self, forKey: .lastStatus)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(lookbackHours, forKey: .lookbackHours)
        try container.encode(selectedMetricIDs, forKey: .selectedMetricIDs)
        try container.encode(includeSamples, forKey: .includeSamples)
        try container.encodeIfPresent(lastSentAt, forKey: .lastSentAt)
        try container.encodeIfPresent(lastStatus, forKey: .lastStatus)
    }
}
