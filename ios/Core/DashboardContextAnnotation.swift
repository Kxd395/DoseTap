import Foundation

/// Version observed on a source response. Its observation time is not a rollout date.
public struct DashboardContentObservation: Codable, Equatable, Sendable {
    public let sourceRecordID: String
    public let instrumentID: String
    public let contentVersion: String?
    public let language: String?
    public let observedAt: Date
    public init(sourceRecordID: String, instrumentID: String, contentVersion: String?, language: String?, observedAt: Date) throws {
        self.sourceRecordID = sourceRecordID; self.instrumentID = instrumentID
        self.contentVersion = contentVersion; self.language = language; self.observedAt = observedAt
        try validate()
    }
    func validate() throws {
        guard ([sourceRecordID, instrumentID] + [contentVersion, language].compactMap { $0 }).allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains("\0") && $0.utf8.count <= 4096
        }), observedAt.timeIntervalSince1970.isFinite else { throw MedicationPresetError.invalidIdentity }
    }
    var compatibilityKey: String {
        contextKey([instrumentID, contentVersion == nil ? "missing" : "present", contentVersion ?? "",
                    language == nil ? "missing" : "present", language ?? ""])
    }
}

/// Derived export evidence; medication label reference, administration and content observations remain distinct.
public struct DashboardContextAnnotation: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case labelReferenceStart, labelReferenceEnd, administration, questionnaireContent }
    public let id: String
    public let kind: Kind
    public let effectiveAt: Date?
    public let observedAt: Date
    public let source: String
    public let sourceRecordIDs: [String]
    public let definitionVersion: String
    public let title: String
    public let detail: String
    public let needsReview: Bool
}

public struct DashboardContextStratum: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case documentedReference, unknown, crossesChange }
    public let id: String
    public let status: Status
    public let label: String
    public let sourceRecordIDs: [String]
    public static func unknown(observationID: String) -> Self {
        .init(id: "context:unknown:" + contextKey([observationID]), status: .unknown,
            label: "Context unknown — kept separate", sourceRecordIDs: [])
    }
}

private func contextKey(_ fields: [String]) -> String {
    fields.map { "\($0.utf8.count):\($0)" }.joined()
}

/// Current immutable schema1 source ledger. This is not a verified prescription history.
public struct DashboardContextTimeline: Sendable {
    public let definitionVersion = "dashboard_context_v1"
    public let capturedAt: Date
    public let annotations: [DashboardContextAnnotation]
    private let chains: [[MedicationPresetRevision]]

    public init(presets: MedicationPresetExportSnapshot, content: [DashboardContentObservation], capturedAt: Date) throws {
        guard capturedAt.timeIntervalSince1970.isFinite else { throw MedicationPresetError.invalidTime }
        self.capturedAt = capturedAt
        let revisions = try presets.presetRevisions.map(MedicationPresetExportSnapshot.decodePreset)
        let administrations = try presets.administrations.map(MedicationPresetExportSnapshot.decodeAdministration)
        guard revisions.allSatisfy({ $0.recordedAt <= capturedAt }), administrations.allSatisfy({ $0.recordedAt <= capturedAt }),
              Set(content.map(\.sourceRecordID)).count == content.count else { throw MedicationPresetError.invalidIdentity }
        for observation in content {
            try observation.validate()
            guard observation.observedAt <= capturedAt else { throw MedicationPresetError.invalidTime }
        }
        chains = Dictionary(grouping: revisions, by: \.presetID).values.map { values in
            let children = Dictionary(uniqueKeysWithValues: values.compactMap { value in value.supersedesRevisionID.map { ($0, value) } })
            var ordered: [MedicationPresetRevision] = [], cursor = values.first { $0.supersedesRevisionID == nil }
            while let next = cursor { ordered.append(next); cursor = children[next.revisionID] }
            return ordered
        }
        var result: [DashboardContextAnnotation] = []
        for revision in revisions {
            let record = revision.revisionID.uuidString
            let amount = NSDecimalNumber(decimal: try revision.totalMilligrams).stringValue
            let detail = "Patient-entered label reference: \(revision.ingredient), \(amount) mg, \(revision.releaseProfile.rawValue). This is not proof of administration or a verified prescription."
            result.append(.init(id: "context:label:\(record):start", kind: .labelReferenceStart,
                effectiveAt: revision.effectiveFrom, observedAt: revision.recordedAt, source: revision.source.rawValue,
                sourceRecordIDs: [record], definitionVersion: "medication_preset_ledger_schema1/context_v1",
                title: "\(revision.labelName): label reference effective", detail: detail, needsReview: false))
            if let end = revision.effectiveUntil {
                result.append(.init(id: "context:label:\(record):end", kind: .labelReferenceEnd, effectiveAt: end,
                    observedAt: revision.recordedAt, source: revision.source.rawValue, sourceRecordIDs: [record],
                    definitionVersion: "medication_preset_ledger_schema1/context_v1", title: "\(revision.labelName): reference period ends",
                    detail: "Explicit end of the stored reference period; not evidence that medication was stopped.", needsReview: false))
            }
        }
        for actual in administrations {
            let amount = NSDecimalNumber(decimal: try actual.totalMilligrams).stringValue
            result.append(.init(id: "context:administration:\(actual.id.uuidString)", kind: .administration,
                effectiveAt: actual.occurredAt, observedAt: actual.recordedAt, source: actual.source.rawValue,
                sourceRecordIDs: [actual.id.uuidString, actual.preset.revisionID.uuidString],
                definitionVersion: "confirmed_medication_administration_schema1/context_v1",
                title: "\(actual.preset.labelName): recorded administration",
                detail: "Reported actual amount \(amount) mg; occurrence precision: \(actual.precision.rawValue). Recording time does not replace an unknown occurrence time.",
                needsReview: actual.precision == .unknown))
        }
        for observation in content {
            result.append(.init(id: "context:content:" + contextKey([observation.sourceRecordID]), kind: .questionnaireContent,
                effectiveAt: nil, observedAt: observation.observedAt, source: "storedQuestionnaireVersion",
                sourceRecordIDs: [observation.sourceRecordID], definitionVersion: "questionnaire_content_observation_v1",
                title: "\(observation.instrumentID): \(observation.contentVersion ?? "version unknown")",
                detail: "Version recorded on this response; rollout/effective date not collected. Language: \(observation.language ?? "not recorded").",
                needsReview: true))
        }
        annotations = result.sorted {
            let a = $0.effectiveAt ?? $0.observedAt, b = $1.effectiveAt ?? $1.observedAt
            return a == b ? $0.id < $1.id : a < b
        }
    }

    /// Half-open elapsed window. A point observation has no end; no calendar-date reconstruction.
    public func stratum(observationID: String, start: Date?, end: Date?, content: [DashboardContentObservation]) -> DashboardContextStratum {
        guard !observationID.isEmpty, let start, start.timeIntervalSince1970.isFinite, start <= capturedAt,
              end.map({ $0.timeIntervalSince1970.isFinite && $0 >= start && $0 <= capturedAt }) ?? true,
              content.allSatisfy({ (try? $0.validate()) != nil && $0.contentVersion != nil && $0.observedAt <= capturedAt }) else {
            return .unknown(observationID: observationID)
        }
        let versions = Dictionary(grouping: content, by: \.instrumentID)
        guard versions.values.allSatisfy({ Set($0.map(\.compatibilityKey)).count == 1 }) else { return .unknown(observationID: observationID) }
        let active = references(at: start), ids = active.map { $0.revisionID.uuidString }.sorted()
        if let end, end > start {
            let boundaries = Set(chains.flatMap { $0 }.flatMap { [$0.effectiveFrom, $0.effectiveUntil].compactMap { $0 } })
            if boundaries.contains(where: { $0 > start && $0 < end && references(at: $0).map { $0.revisionID.uuidString }.sorted() != ids }) {
                return .init(id: "context:crosses:" + contextKey([observationID]), status: .crossesChange,
                    label: "Observation spans a reference change — kept separate", sourceRecordIDs: ids)
            }
        }
        guard !active.isEmpty else { return .unknown(observationID: observationID) }
        let contentKeys = Set(content.map(\.compatibilityKey)).sorted()
        return .init(id: "context:v1:" + contextKey(["references"] + ids + ["content"] + contentKeys), status: .documentedReference,
            label: "Patient-entered reference: " + active.map(\.labelName).sorted().joined(separator: ", ")
                + (content.isEmpty ? "" : " · " + Set(content.map { "\($0.instrumentID) \($0.contentVersion!)" }).sorted().joined(separator: ", ")),
            sourceRecordIDs: ids + content.map(\.sourceRecordID).sorted())
    }

    /// Unplaced annotations are selected by observedAt but retain nil effectiveAt.
    /// Baseline records retain their original effective date; they are never moved to the range start.
    public func annotations(from start: Date, to end: Date, includeBaseline: Bool) -> [DashboardContextAnnotation] {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, start < end else { return [] }
        let baseline = includeBaseline ? Set(references(at: start).map { $0.revisionID.uuidString }) : []
        return annotations.filter { row in
            if let time = row.effectiveAt {
                return (time >= start && time < end) || (row.kind == .labelReferenceStart && time < start && !baseline.isDisjoint(with: row.sourceRecordIDs))
            }
            return row.observedAt >= start && row.observedAt < end
        }
    }

    private func references(at date: Date) -> [MedicationPresetRevision] {
        chains.compactMap { chain in
            // A successor can replace an earlier interval retroactively, but cannot resurrect an expired predecessor.
            guard let latest = chain.last(where: { $0.effectiveFrom <= date }), latest.isEffective(at: date) else { return nil }
            return latest
        }
    }
}
