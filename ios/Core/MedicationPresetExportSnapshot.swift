import Foundation

/// Opaque canonical payloads keep Decimal values out of lossy generic JSON-number projections.
public struct MedicationPresetExportSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let presetRevisions: [String]
    public let administrations: [String]

    public init(presetRevisions: [String], administrations: [String]) throws {
        schemaVersion = 1
        self.presetRevisions = presetRevisions
        self.administrations = administrations
        try validate()
    }

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decodePreset(_ payload: String) throws -> MedicationPresetRevision {
        try JSONDecoder().decode(MedicationPresetRevision.self, from: Data(payload.utf8))
    }

    public static func decodeAdministration(_ payload: String) throws -> ConfirmedMedicationAdministration {
        try JSONDecoder().decode(ConfirmedMedicationAdministration.self, from: Data(payload.utf8))
    }

    private func validate() throws {
        guard schemaVersion == 1 else { throw MedicationPresetError.unsupportedVersion }
        let presets = try presetRevisions.map(Self.decodePreset)
        guard Set(presets.map(\.revisionID)).count == presets.count else { throw MedicationPresetError.invalidIdentity }
        let byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.revisionID, $0) })
        var roots = Set<UUID>(), parents = Set<UUID>()
        for preset in presets {
            if let previous = preset.supersedesRevisionID {
                guard let parent = byID[previous], parent.presetID == preset.presetID,
                      parent.recordedAt <= preset.recordedAt, parents.insert(previous).inserted else {
                    throw MedicationPresetError.invalidIdentity
                }
                var seen = Set([preset.revisionID]), cursor: UUID? = previous
                while let current = cursor {
                    guard seen.insert(current).inserted else { throw MedicationPresetError.invalidIdentity }
                    cursor = byID[current]?.supersedesRevisionID
                }
            } else if !roots.insert(preset.presetID).inserted { throw MedicationPresetError.invalidIdentity }
        }
        var administrationIDs = Set<UUID>()
        for payload in administrations {
            let actual = try Self.decodeAdministration(payload)
            guard administrationIDs.insert(actual.id).inserted,
                  byID[actual.preset.revisionID] == actual.preset else { throw MedicationPresetError.invalidIdentity }
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, presetRevisions, administrations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        presetRevisions = try c.decode([String].self, forKey: .presetRevisions)
        administrations = try c.decode([String].self, forKey: .administrations)
        try validate()
    }
}
