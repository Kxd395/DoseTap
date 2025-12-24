import Foundation

enum DataSource: String, Codable, CaseIterable, Identifiable {
    case whoop
    case apple_health
    case manual
    var id: String { rawValue }
}

enum DataMetric: String, Codable, CaseIterable, Identifiable {
    case heart_rate
    case respiratory_rate
    case oxygen_saturation
    case hrv_sdnn
    case sleep_stage
    case medication_event
    case bathroom_event
    var id: String { rawValue }
}

struct SavedDatum: Codable, Identifiable {
    var id: UUID = UUID()
    var user_id: String
    var timestamp: Date
    var source: DataSource
    var metric: DataMetric
    var valueString: String?
    var valueNumber: Double?
    var notes: String?
    var tags: [String]?

    enum CodingKeys: String, CodingKey { case user_id, timestamp, source, metric, value, notes, tags, id }

    init(user_id: String, timestamp: Date, source: DataSource, metric: DataMetric, valueString: String? = nil, valueNumber: Double? = nil, notes: String? = nil, tags: [String]? = nil) {
        self.user_id = user_id
        self.timestamp = timestamp
        self.source = source
        self.metric = metric
        self.valueString = valueString
        self.valueNumber = valueNumber
        self.notes = notes
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.user_id = try c.decode(String.self, forKey: .user_id)
        let tsString = try c.decode(String.self, forKey: .timestamp)
        if let date = ISO8601DateFormatter().date(from: tsString) {
            self.timestamp = date
        } else if let date = ISO8601DateFormatter().date(from: tsString.replacingOccurrences(of: "Z", with: "+00:00")) {
            self.timestamp = date
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.timestamp], debugDescription: "Invalid ISO8601 date"))
        }
        self.source = try c.decode(DataSource.self, forKey: .source)
        self.metric = try c.decode(DataMetric.self, forKey: .metric)
        self.notes = try? c.decode(String.self, forKey: .notes)
        self.tags = try? c.decode([String].self, forKey: .tags)

        // value can be number or string
        if let number = try? c.decode(Double.self, forKey: .value) {
            self.valueNumber = number
            self.valueString = nil
        } else if let str = try? c.decode(String.self, forKey: .value) {
            self.valueString = str
            self.valueNumber = nil
        } else {
            self.valueString = nil
            self.valueNumber = nil
        }
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user_id, forKey: .user_id)
        try c.encode(timestamp.ISO8601Format(), forKey: .timestamp)
        try c.encode(source, forKey: .source)
        try c.encode(metric, forKey: .metric)
        if let n = valueNumber { try c.encode(n, forKey: .value) }
        else if let s = valueString { try c.encode(s, forKey: .value) }
        if let notes = notes { try c.encode(notes, forKey: .notes) }
        if let tags = tags { try c.encode(tags, forKey: .tags) }
        try c.encode(id, forKey: .id)
    }

    var displayValue: String {
        if let n = valueNumber {
            if metric == .oxygen_saturation { return String(format: "%.0f%%", n * 100) }
            return String(format: "%.2f", n)
        }
        return valueString ?? "—"
    }
}

struct DashboardFilters {
    var dateStart: Date
    var dateEnd: Date
    var sources: Set<DataSource>
    var metrics: Set<DataMetric>
}

