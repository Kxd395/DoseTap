import Foundation
import DoseCore

private struct PhysicianWakeReference: Encodable {
    let sourceID: String, revision: String
    let at: Date
    init(_ source: DaytimeWakeReference) { sourceID = source.sourceID; revision = source.revision; at = source.at }
}
private struct PhysicianWakeEvidence: Encodable {
    let definitionVersion: Int, status: String
    let elapsedSeconds: Double?, elapsedHourBand: Int?
    let originalReferences: [PhysicianWakeReference]
    let currentSource: PhysicianWakeReference?, currentSourceRecordedAt: Date?
    init(_ source: DaytimeWakeContext) {
        definitionVersion = source.definitionVersion; status = source.status.rawValue
        elapsedSeconds = source.elapsedSeconds; elapsedHourBand = source.elapsedHourBand
        originalReferences = source.originalReferences.map(PhysicianWakeReference.init)
        currentSource = source.currentSource.map { PhysicianWakeReference($0.reference) }
        currentSourceRecordedAt = source.currentSource?.recordedAt
    }
}
private struct PhysicianDaytimeContextEvidence: Encodable {
    let definitionVersion: Int
    let observationID: UUID, observationRevisionID: UUID, workDocumentRevision: UUID?
    let assessedAt: Date, asOf: Date
    let groupingKey: String, label: String, workStatus: String, workBasis: String
    let workCandidates: [WorkShiftEvent]
    let medicationStratumID: String, medicationStatus: String, medicationSourceRecordIDs: [String]
    let wake: PhysicianWakeEvidence?
    init(_ source: DaytimeObservationContext) {
        definitionVersion = source.definitionVersion; observationID = source.observationID
        observationRevisionID = source.observationRevisionID; assessedAt = source.assessedAt; asOf = source.asOf
        groupingKey = source.groupingKey; label = source.label
        workDocumentRevision = source.work.documentRevision; workStatus = source.work.status.rawValue
        workBasis = source.work.basis.rawValue; workCandidates = source.work.candidates
        medicationStratumID = source.medication.id; medicationStatus = source.medication.status.rawValue
        medicationSourceRecordIDs = source.medication.sourceRecordIDs; wake = source.wake.map(PhysicianWakeEvidence.init)
    }
}
func physicianDaytimeContextPayload(_ context: DaytimeObservationContext?) throws -> String {
    guard let context else { return "Context not evaluated" }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
    return "Frozen context (Unix-second timestamps; missing wake means not evaluated): "
        + String(decoding: try encoder.encode(PhysicianDaytimeContextEvidence(context)), as: UTF8.self)
}
