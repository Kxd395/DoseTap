import Foundation

public enum MedicationAmendmentAction: String, Codable, Sendable { case correction, reversal }
public enum MedicationAmendmentSource: String, Codable, Sendable { case userConfirmedAmendment }

/// Audit evidence only. A replacement belongs to the original ID, not a new administration.
public struct MedicationAdministrationAmendment: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let administrationID: UUID
    public let supersedesAmendmentID: UUID?
    public let action: MedicationAmendmentAction
    public let replacement: ConfirmedMedicationAdministration?
    public let reason: String
    public let confirmedAt: Date
    public let recordedAt: Date
    public let source: MedicationAmendmentSource

    public init(id: UUID, administrationID: UUID, supersedesAmendmentID: UUID?,
                action: MedicationAmendmentAction, replacement: ConfirmedMedicationAdministration?,
                reason: String, confirmedAt: Date, recordedAt: Date) throws {
        schemaVersion = 1
        self.id = id
        self.administrationID = administrationID
        self.supersedesAmendmentID = supersedesAmendmentID
        self.action = action
        self.replacement = replacement
        self.reason = reason
        self.confirmedAt = confirmedAt
        self.recordedAt = recordedAt
        source = .userConfirmedAmendment
        try validate()
    }

    private func validate() throws {
        guard schemaVersion == 1 else { throw MedicationPresetError.unsupportedVersion }
        guard id != administrationID, id != supersedesAmendmentID,
              supersedesAmendmentID != administrationID,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MedicationPresetError.invalidIdentity
        }
        guard confirmedAt.timeIntervalSince1970.isFinite, recordedAt.timeIntervalSince1970.isFinite,
              confirmedAt <= recordedAt else { throw MedicationPresetError.invalidTime }
        switch action {
        case .correction:
            guard let replacement, replacement.id == administrationID,
                  replacement.confirmedAt == confirmedAt, replacement.recordedAt == recordedAt else {
                throw MedicationPresetError.invalidIdentity
            }
        case .reversal:
            guard replacement == nil else { throw MedicationPresetError.invalidIdentity }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, administrationID, supersedesAmendmentID, action, replacement
        case reason, confirmedAt, recordedAt, source
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        administrationID = try c.decode(UUID.self, forKey: .administrationID)
        supersedesAmendmentID = try c.decodeIfPresent(UUID.self, forKey: .supersedesAmendmentID)
        action = try c.decode(MedicationAmendmentAction.self, forKey: .action)
        replacement = try c.decodeIfPresent(ConfirmedMedicationAdministration.self, forKey: .replacement)
        reason = try c.decode(String.self, forKey: .reason)
        confirmedAt = try c.decode(Date.self, forKey: .confirmedAt)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        source = try c.decode(MedicationAmendmentSource.self, forKey: .source)
        try validate()
    }
}

public struct ReviewedMedicationAdministration: Equatable, Sendable {
    public let original: ConfirmedMedicationAdministration
    public let amendments: [MedicationAdministrationAmendment]
    /// Nil means withdrawn evidence, not a skipped or confirmed-not-taken outcome.
    public var current: ConfirmedMedicationAdministration? {
        guard let latest = amendments.last else { return original }
        return latest.replacement
    }
}

public enum MedicationAdministrationAudit {
    /// Pure projection; intentionally not part of the schema1 persisted/exported ledger.
    public static func project(snapshot: MedicationPresetExportSnapshot,
                               amendments: [MedicationAdministrationAmendment]) throws -> [ReviewedMedicationAdministration] {
        let originals = try snapshot.administrations.map(MedicationPresetExportSnapshot.decodeAdministration)
        let presets = try snapshot.presetRevisions.map(MedicationPresetExportSnapshot.decodePreset)
        let presetByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.revisionID, $0) })
        let rootIDs = Set(originals.map(\.id))
        var seenIDs = rootIDs
        for amendment in amendments {
            guard rootIDs.contains(amendment.administrationID), seenIDs.insert(amendment.id).inserted else {
                throw MedicationPresetError.invalidIdentity
            }
            if let replacement = amendment.replacement,
               presetByID[replacement.preset.revisionID] != replacement.preset {
                throw MedicationPresetError.invalidIdentity
            }
        }
        let groups = Dictionary(grouping: amendments, by: \.administrationID)
        return try originals.sorted {
            $0.recordedAt == $1.recordedAt ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt < $1.recordedAt
        }.map { original in
            let candidates = groups[original.id] ?? []
            var children: [UUID: MedicationAdministrationAmendment] = [:]
            // The root ID is a sentinel only; persisted first amendments have a nil predecessor.
            for candidate in candidates {
                let parent = candidate.supersedesAmendmentID ?? original.id
                guard children.updateValue(candidate, forKey: parent) == nil else {
                    throw MedicationPresetError.invalidIdentity
                }
            }
            var chain: [MedicationAdministrationAmendment] = []
            var cursor = original.id
            var previousTime = original.recordedAt
            var reversed = false
            while let next = children.removeValue(forKey: cursor) {
                guard !reversed, next.confirmedAt >= previousTime else { throw MedicationPresetError.invalidTime }
                chain.append(next)
                cursor = next.id
                previousTime = next.recordedAt
                reversed = next.action == .reversal
            }
            // Orphans, cycles and cross-root links cannot be reached from this root.
            guard children.isEmpty else { throw MedicationPresetError.invalidIdentity }
            return ReviewedMedicationAdministration(original: original, amendments: chain)
        }
    }
}
