import Foundation

/// Original local archive rows. These do not imply a treatment-night association.
public struct StudioIndependentSourceRecord: Codable, Hashable, Sendable {
    public static let primaryKeys = [
        "dashboard_dose_reviews": "observation_id", "dashboard_provider_associations": "episode_id",
        "daytime_checkins": "revision_id", "daytime_events": "revision_id", "daytime_prompt_state": "id",
        "physician_review_records": "id", "work_block_context": "id", "nap_diary": "id"
    ]
    public static var sourceTables: [String] { primaryKeys.keys.sorted() }
    public let sourceTable: String
    public let columns: [String: Value]
    public var recordID: String { columns[Self.primaryKeys[sourceTable]!]!.identifier! }

    private enum CodingKeys: String, CodingKey { case sourceTable, columns }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceTable = try c.decode(String.self, forKey: .sourceTable)
        columns = try c.decode([String: Value].self, forKey: .columns)
        guard let primaryKey = Self.primaryKeys[sourceTable], let id = columns[primaryKey]?.identifier,
              !id.isEmpty, columns.keys.allSatisfy({ !$0.isEmpty }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Independent source row requires a supported table and original identity"))
        }
    }

    public struct Value: Codable, Hashable, Sendable {
        public let type: String
        public let text: String?
        public let integer: Int64?
        public let real: Double?
        public let blobBase64: String?
        var identifier: String? { type == "text" ? text : type == "integer" ? integer.map(String.init) : nil }
        var originalValue: Any {
            switch type {
            case "text": return text!
            case "integer": return integer!
            case "real": return real!
            case "blob": return blobBase64!
            default: return NSNull()
            }
        }
        private enum CodingKeys: String, CodingKey { case type, text, integer, real, blobBase64 }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            text = try c.decodeIfPresent(String.self, forKey: .text)
            integer = try c.decodeIfPresent(Int64.self, forKey: .integer)
            real = try c.decodeIfPresent(Double.self, forKey: .real)
            blobBase64 = try c.decodeIfPresent(String.self, forKey: .blobBase64)
            let values = [text != nil, integer != nil, real != nil, blobBase64 != nil].filter { $0 }.count
            let valid: Bool
            switch type {
            case "null": valid = values == 0
            case "text": valid = values == 1 && text != nil
            case "integer": valid = values == 1 && integer != nil
            case "real": valid = values == 1 && real?.isFinite == true
            case "blob": valid = values == 1 && blobBase64.flatMap { Data(base64Encoded: $0) } != nil
            default: valid = false
            }
            guard valid else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Independent source column has an invalid SQLite type/value pair"))
            }
        }
    }
}
