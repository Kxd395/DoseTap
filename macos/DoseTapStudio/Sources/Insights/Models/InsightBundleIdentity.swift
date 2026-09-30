import Foundation
import DoseCore

struct InsightBundleImportMetadata: Codable, Hashable, Sendable {
    let fileName: String
    let byteCount: Int
    let sha256Hex: String
    let importedAtUTC: Date
}

struct InsightDoseTimingReview: Codable, Hashable, Sendable {
    let version: Int
    let status: String
    let reason: String
    let derivationVersion: String?
    let rawIntervalSeconds: Double?
    let intervalSeconds: Double?
    var eligibleSeconds: Double? {
        guard version == 1, status == "available", reason == "available",
              let intervalSeconds, intervalSeconds.isFinite, intervalSeconds > 0 else { return nil }
        return intervalSeconds
    }
}


struct InsightIdentityResolution: Codable, Hashable, Sendable {
    let version: Int
    let status: String
    let sessionIds: [String]
    let reasons: [String]

    var permitsDerivedSummary: Bool { version == 1 && status == "resolved" }
}

struct InsightRawSourceRecord: Codable, Hashable, Sendable {
    let sourceTable: String
    let columns: [String: InsightRawSourceValue]
}

struct InsightRawSourceValue: Codable, Hashable, Sendable {
    let type: String
    let text: String?
    let integer: Int64?
    let real: Double?
    let blobBase64: String?
}

extension InsightBundle {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportVersion, appVersion, exportedAtUTC, timeZoneIdentifier, localOffsetMinutes
        case consent, exportWarnings, whoopEnrichment, importMetadata, sessions, dateGroups, medicationPresetLedger, independentSourceRecords, archiveScope, independentRecordsIncluded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard [1, 2, 3, 4, 5, 6].contains(schemaVersion), !c.contains(schemaVersion >= 3 ? .sessions : .dateGroups) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported bundle schema or contradictory session layout"))
        }
        if schemaVersion >= 5 {
            medicationPresetLedger = try c.decode(MedicationPresetExportSnapshot.self, forKey: .medicationPresetLedger)
        } else {
            guard !c.contains(.medicationPresetLedger) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Medication ledger requires schema 5"))
            }
            medicationPresetLedger = nil
        }
        archiveScope = try c.decodeIfPresent(String.self, forKey: .archiveScope)
        independentRecordsIncluded = try c.decodeIfPresent(Bool.self, forKey: .independentRecordsIncluded)
        if schemaVersion == 6 {
            guard archiveScope == "manual_full_local_records", independentRecordsIncluded == true else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Schema 6 requires explicit full local archive scope"))
            }
            independentSourceRecords = try c.decode([StudioIndependentSourceRecord].self, forKey: .independentSourceRecords)
        } else {
            guard !c.contains(.independentSourceRecords) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Independent source rows require schema 6"))
            }
            guard (archiveScope == nil && independentRecordsIncluded == nil) ||
                    (archiveScope == "local_subset" && independentRecordsIncluded == false) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Legacy scope cannot claim independent records"))
            }
            independentSourceRecords = nil
        }
        exportVersion = try c.decodeIfPresent(String.self, forKey: .exportVersion)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        exportedAtUTC = try c.decode(Date.self, forKey: .exportedAtUTC)
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        localOffsetMinutes = try c.decodeIfPresent(Int.self, forKey: .localOffsetMinutes)
        consent = try c.decodeIfPresent(InsightConsentState.self, forKey: .consent)
        exportWarnings = try c.decodeIfPresent([String].self, forKey: .exportWarnings)
        whoopEnrichment = try c.decodeIfPresent(InsightWHOOPEnrichment.self, forKey: .whoopEnrichment)
        importMetadata = try c.decodeIfPresent(InsightBundleImportMetadata.self, forKey: .importMetadata)
        sessions = try c.decode([InsightSessionSupplement].self, forKey: schemaVersion >= 3 ? .dateGroups : .sessions)
        guard schemaVersion < 4 || sessions.allSatisfy({ $0.doseTimingReview != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Schema 4 requires dose timing review"))
        }
        guard schemaVersion < 3 || sessions.allSatisfy({ $0.identityResolution != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Schema 3 date groups require identity resolution"))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard [1, 2, 3, 4, 5, 6].contains(schemaVersion), (schemaVersion >= 5) == (medicationPresetLedger != nil), (schemaVersion == 6) == (independentSourceRecords != nil), schemaVersion < 3 || sessions.allSatisfy({ $0.identityResolution != nil }) else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported bundle schema or missing identity resolution"))
        }
        guard schemaVersion != 6 || (archiveScope == "manual_full_local_records" && independentRecordsIncluded == true) else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Schema 6 requires explicit full local archive scope"))
        }
        guard schemaVersion == 6 || (archiveScope == nil && independentRecordsIncluded == nil) ||
                (archiveScope == "local_subset" && independentRecordsIncluded == false) else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Legacy scope cannot claim independent records"))
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(exportVersion, forKey: .exportVersion)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
        try c.encode(exportedAtUTC, forKey: .exportedAtUTC)
        try c.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try c.encodeIfPresent(localOffsetMinutes, forKey: .localOffsetMinutes)
        try c.encodeIfPresent(consent, forKey: .consent)
        try c.encodeIfPresent(exportWarnings, forKey: .exportWarnings)
        try c.encodeIfPresent(whoopEnrichment, forKey: .whoopEnrichment)
        try c.encodeIfPresent(importMetadata, forKey: .importMetadata)
        try c.encodeIfPresent(medicationPresetLedger, forKey: .medicationPresetLedger)
        try c.encodeIfPresent(independentSourceRecords, forKey: .independentSourceRecords)
        try c.encodeIfPresent(archiveScope, forKey: .archiveScope)
        try c.encodeIfPresent(independentRecordsIncluded, forKey: .independentRecordsIncluded)
        try c.encode(sessions, forKey: schemaVersion >= 3 ? .dateGroups : .sessions)
    }
}
