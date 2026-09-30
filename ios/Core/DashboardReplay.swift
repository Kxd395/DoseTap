import Foundation

/// Explicitly selected occurrence endpoints. Recording time is never substituted.
public struct DashboardReplayMarker: Codable, Equatable, Identifiable, Sendable {
    public struct EvidenceQuality: Codable, Equatable, Sendable {
        public let state: DashboardMetricState
        public let reason: String
        public let capturedAt: Date?
        public let providerRecordID: String?
        public init(state: DashboardMetricState, reason: String, capturedAt: Date?, providerRecordID: String? = nil) {
            self.state = state; self.reason = reason; self.capturedAt = capturedAt; self.providerRecordID = providerRecordID
        }
    }
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case dose1, dose2, extraDose, foodFinish, caffeine, returnSleep, deviceSleepEnd, reportedWake, requiredWake
        case medicationXR, medicationIR, daytimeMedication, mainSleepStart, napEnd, reminder, alarmDelivered, event
        case whoopEpisodeStart, whoopEpisodeEnd
        public var isProviderDerived: Bool { [.mainSleepStart, .deviceSleepEnd, .returnSleep, .whoopEpisodeStart, .whoopEpisodeEnd].contains(self) }
        public var label: String {
            switch self {
            case .dose1: return "Dose 1"
            case .dose2: return "Dose 2"
            case .extraDose: return "Additional administration"
            case .foodFinish: return "Reported food finished"
            case .caffeine: return "Reported caffeine"
            case .returnSleep: return "Observed return to sleep"
            case .deviceSleepEnd: return "Device last observed sleep end"
            case .reportedWake: return "Patient-reported final wake"
            case .requiredWake: return "Historical required wake"
            case .medicationXR: return "Selected XR administration"
            case .medicationIR: return "Selected IR administration"
            case .daytimeMedication: return "Selected daytime administration"
            case .mainSleepStart: return "Selected main sleep start"
            case .napEnd: return "Selected nap end"
            case .reminder: return "Saved reminder target"
            case .alarmDelivered: return "Recorded alarm delivery"
            case .event: return "Recorded event"
            case .whoopEpisodeStart: return "WHOOP original episode start"
            case .whoopEpisodeEnd: return "WHOOP original episode end"
            }
        }
    }
    public let id: String
    public let sessionID: String
    public let kind: Kind
    public let occurredAt: Date
    public let recordedAt: Date?
    public let source: String
    public let sourceRecordID: String?
    public let medicationID: String?
    public let formulation: String?
    public let amountDescription: String?
    public let evidenceQuality: EvidenceQuality?
    public init(id: String, sessionID: String, kind: Kind, occurredAt: Date, recordedAt: Date? = nil, source: String,
                sourceRecordID: String? = nil, medicationID: String? = nil, formulation: String? = nil,
                amountDescription: String? = nil, evidenceQuality: EvidenceQuality? = nil) {
        self.id = id; self.sessionID = sessionID; self.kind = kind; self.occurredAt = occurredAt
        self.recordedAt = recordedAt; self.source = source; self.sourceRecordID = sourceRecordID ?? id
        self.medicationID = medicationID; self.formulation = formulation; self.amountDescription = amountDescription
        self.evidenceQuality = evidenceQuality
    }
}

public enum DashboardIntervalPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case dose1ToDose2 = "Dose 1 to Dose 2", foodToDose1 = "Food to Dose 1"
    case dose2ToSleep = "Dose 2 to subsequent observed sleep", dose2ToDeviceEnd = "Dose 2 to device sleep end"
    case dose2ToReportedWake = "Dose 2 to reported final wake", dose2ToRequiredWake = "Dose 2 to required wake"
    case caffeineToDose1 = "Last caffeine to Dose 1", xrToIR = "Selected XR to IR"
    case medicationToSleep = "Daytime medication to main sleep", napToSleep = "Nap end to main sleep"
    case reminderDeviation = "Administration minus saved reminder", deliveredAlarmToDose = "Delivered alarm to administration"
    case dose2ToWHOOPepisodeEnd = "Dose 2 to WHOOP original episode end"
    case medicationToWHOOPepisodeStart = "Daytime medication to WHOOP original episode start"
    case napToWHOOPepisodeStart = "Nap end to WHOOP original episode start"
    public var id: String { rawValue }
    public var endpoints: (DashboardReplayMarker.Kind, DashboardReplayMarker.Kind) {
        switch self {
        case .dose1ToDose2: return (.dose1, .dose2)
        case .foodToDose1: return (.foodFinish, .dose1)
        case .dose2ToSleep: return (.dose2, .returnSleep)
        case .dose2ToDeviceEnd: return (.dose2, .deviceSleepEnd)
        case .dose2ToReportedWake: return (.dose2, .reportedWake)
        case .dose2ToRequiredWake: return (.dose2, .requiredWake)
        case .caffeineToDose1: return (.caffeine, .dose1)
        case .xrToIR: return (.medicationXR, .medicationIR)
        case .medicationToSleep: return (.daytimeMedication, .mainSleepStart)
        case .napToSleep: return (.napEnd, .mainSleepStart)
        case .reminderDeviation: return (.reminder, .dose2)
        case .deliveredAlarmToDose: return (.alarmDelivered, .dose2)
        case .dose2ToWHOOPepisodeEnd: return (.dose2, .whoopEpisodeEnd)
        case .medicationToWHOOPepisodeStart: return (.daytimeMedication, .whoopEpisodeStart)
        case .napToWHOOPepisodeStart: return (.napEnd, .whoopEpisodeStart)
        }
    }
}

public struct DashboardIntervalObservation: Codable, Equatable, Sendable {
    public typealias State = DashboardMetricState
    public let preset: DashboardIntervalPreset
    public let minutes: Double?
    public let state: State
    public let reason: String
    public let startID: String?
    public let endID: String?
    public func eligibleMinutes(includePartial: Bool = false) -> Double? {
        guard state == .available || (includePartial && state == .partial), let minutes, minutes.isFinite else { return nil }
        return minutes
    }
    public var referenceVersion: String? { preset == .dose1ToDose2 ? "dose_spacing_reference_v1_150_240_minutes" : nil }
    public var referenceGroup: String? {
        guard preset == .dose1ToDose2, let minutes else { return nil }
        return minutes < 150 ? "Below reference" : minutes <= 240 ? "Within reference" : "Above reference"
    }
}

/// Immutable report of selected evidence; later corrections create a different snapshot.
public struct DashboardReplaySnapshot: Codable, Equatable, Sendable {
    public enum Alignment: String, CaseIterable, Identifiable, Sendable {
        case clock = "Clock time", dose1 = "Since Dose 1", dose2 = "Since Dose 2"
        public var id: String { rawValue }
    }
    public let derivationVersion: String
    public let timestampEncoding: String
    public let sessionID: String
    public let treatmentDate: String
    public let asOf: Date
    public let timeZoneID: String
    public let sourcePolicy: String
    public let filterDescription: String
    public let markers: [DashboardReplayMarker]
    public let dose2NotTaken: Bool
    public let identityResolved: Bool
    public let reviewedProjection: ReviewedNightSleepProjection?
    public let mainEpisodeIntervals: [RecordedSleepInterval]
    public struct DosePairSelection: Codable, Equatable, Sendable {
        public let dose1ID: String
        public let dose2ID: String
        public init(dose1ID: String, dose2ID: String) { self.dose1ID = dose1ID; self.dose2ID = dose2ID }
    }
    public let dosePairSelection: DosePairSelection?
    public init(sessionID: String, treatmentDate: String, asOf: Date, timeZoneID: String,
                sourcePolicy: String, filterDescription: String, markers: [DashboardReplayMarker],
                dose2NotTaken: Bool = false, identityResolved: Bool = true,
                reviewedProjection: ReviewedNightSleepProjection? = nil, mainEpisodeIntervals: [RecordedSleepInterval] = [],
                dosePairSelection: DosePairSelection? = nil) {
        timestampEncoding = "JSON dates: elapsed seconds since 2001-01-01T00:00:00Z; CSV dates: ISO 8601 UTC"
        derivationVersion = "dashboard_replay_v2"; self.sessionID = sessionID; self.treatmentDate = treatmentDate
        self.asOf = asOf; self.timeZoneID = timeZoneID; self.sourcePolicy = sourcePolicy
        self.filterDescription = filterDescription; self.markers = markers.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt
        }
        self.dose2NotTaken = dose2NotTaken; self.identityResolved = identityResolved
        self.reviewedProjection = reviewedProjection; self.mainEpisodeIntervals = mainEpisodeIntervals
        self.dosePairSelection = dosePairSelection
    }
    public var hasValidBoundary: Bool {
        !sessionID.isEmpty && asOf.timeIntervalSinceReferenceDate.isFinite && TimeZone(identifier: timeZoneID) != nil
    }
    /// Render only timestamped imported episode intervals, not reconstructed stages.
    public var mainEpisodeEvidence: SleepEvidenceResolution? {
        guard hasValidBoundary else { return nil }
        guard let start = mainEpisodeIntervals.map(\.start).min(), let end = mainEpisodeIntervals.map(\.end).max() else { return nil }
        guard let result = SleepEvidenceResolution.calculate(start: start, end: end, samples: mainEpisodeIntervals.map {
            .init(sampleID: nil, start: $0.start, end: $0.end, rawCategory: 0, stage: $0.asleep ? .asleep : .awake,
                  origin: .init(sourceName: sourcePolicy, bundleIdentifier: nil))
        }), result.rejectedSampleCount == 0 else { return nil }
        return result
    }
    public func interval(_ preset: DashboardIntervalPreset) -> DashboardIntervalObservation {
        let pair = preset.endpoints
        let starts = endpoints(for: pair.0), ends = endpoints(for: pair.1)
        func result(_ state: DashboardIntervalObservation.State, _ reason: String, _ value: Double? = nil) -> DashboardIntervalObservation {
            .init(preset: preset, minutes: value, state: state, reason: reason,
                  startID: starts.count == 1 ? starts.first?.id : nil, endID: ends.count == 1 ? ends.first?.id : nil)
        }
        guard hasValidBoundary else { return result(.needsReview, "Snapshot identity, as-of time or timezone is invalid") }
        guard identityResolved else { return result(.needsReview, "Session or episode association is unresolved") }
        guard dosePairIsValid else { return result(.needsReview, "Explicit dose pair is no longer valid") }
        if preset == .dose1ToDose2 && dosePairSelection == nil && markers.contains(where: { $0.kind == .extraDose }) {
            return result(.needsReview, "Additional administration requires explicit pair review")
        }
        let selected = starts + ends
        guard selected.allSatisfy({ !$0.id.isEmpty && $0.sessionID == sessionID &&
            $0.occurredAt.timeIntervalSince1970.isFinite && ($0.kind == .requiredWake || $0.kind == .reminder || $0.occurredAt <= asOf) }),
            Set(selected.map(\.id)).count == selected.count, starts.count <= 1, ends.count <= 1 else {
            return result(.needsReview, "Conflicting, duplicate, future or unrelated endpoints")
        }
        if dose2NotTaken && (pair.0 == .dose2 || pair.1 == .dose2) {
            return result(markers.contains { $0.kind == .dose2 } ? .needsReview : .notApplicable,
                          "Dose 2 explicitly reported not taken")
        }
        guard let start = starts.first, let end = ends.first else {
            return result(.unavailable, "Requires explicit \(pair.0.label) and \(pair.1.label) occurrences")
        }
        if preset == .dose2ToSleep {
            guard let projection = reviewedProjection, projection.window.sessionID == sessionID,
                  projection.generatedAt <= asOf else { return result(.unavailable, "Check current reviewed-window evidence first") }
            let bands = projection.bands
            guard let index = bands.indices.first(where: { bands[$0].state == .awake &&
                bands[$0].start <= start.occurredAt && start.occurredAt < bands[$0].end }),
                index > 0, index + 1 < bands.count, bands[index - 1].state == .asleep,
                bands[index + 1].state == .asleep, bands[index].end == end.occurredAt else {
                return result(.needsReview, "No observed awake-to-sleep boundary surrounding Dose 2; gaps are not latency")
            }
        }
        let minutes = end.occurredAt.timeIntervalSince(start.occurredAt) / 60
        let signed = preset == .dose2ToRequiredWake || preset == .reminderDeviation
        guard minutes.isFinite, signed || minutes > 0 else { return result(.needsReview, "Nonpositive endpoint order requires review") }
        let quality = endpointQuality(selected)
        let meaning = signed ? "Signed elapsed minutes; not a safety classification" : "UTC elapsed minutes; not sleep duration"
        guard quality.0 == .available || quality.0 == .partial else { return result(quality.0, quality.1) }
        return result(quality.0, meaning + (quality.1.isEmpty ? "" : "; " + quality.1), minutes)
    }
    private func endpoints(for kind: DashboardReplayMarker.Kind) -> [DashboardReplayMarker] {
        let selectedID = kind == .dose1 ? dosePairSelection?.dose1ID : kind == .dose2 ? dosePairSelection?.dose2ID : nil
        return markers.filter { $0.kind == kind && (selectedID == nil || $0.id == selectedID) }
    }
    private var dosePairIsValid: Bool {
        guard let pair = dosePairSelection else { return true }
        guard identityResolved, !pair.dose1ID.isEmpty, !pair.dose2ID.isEmpty, pair.dose1ID != pair.dose2ID else { return false }
        let first = markers.filter { $0.id == pair.dose1ID }, second = markers.filter { $0.id == pair.dose2ID }
        guard first.count == 1, second.count == 1, let start = first.first, let end = second.first,
              start.kind == .dose1, end.kind == .dose2,
              [start, end].allSatisfy({ $0.sessionID == sessionID && $0.occurredAt.timeIntervalSince1970.isFinite && $0.occurredAt <= asOf }) else { return false }
        return end.occurredAt > start.occurredAt
    }
    public func selectingDosePair(dose1ID: String?, dose2ID: String?) throws -> Self {
        guard hasValidBoundary, (dose1ID == nil) == (dose2ID == nil) else { throw SelectionError.invalidEndpoint }
        let pair = dose1ID.flatMap { first in dose2ID.map { DosePairSelection(dose1ID: first, dose2ID: $0) } }
        let value = Self(sessionID: sessionID, treatmentDate: treatmentDate, asOf: asOf, timeZoneID: timeZoneID,
            sourcePolicy: sourcePolicy, filterDescription: filterDescription, markers: markers,
            dose2NotTaken: dose2NotTaken, identityResolved: identityResolved, reviewedProjection: reviewedProjection,
            mainEpisodeIntervals: mainEpisodeIntervals, dosePairSelection: pair)
        guard value.dosePairIsValid else { throw SelectionError.invalidEndpoint }
        return value
    }
    private func endpointQuality(_ endpoints: [DashboardReplayMarker]) -> (DashboardMetricState, String) {
        var states: [DashboardMetricState] = [], reasons: [String] = []
        for marker in endpoints where marker.kind.isProviderDerived || marker.evidenceQuality != nil {
            guard let quality = marker.evidenceQuality else {
                states.append(.partial); reasons.append("Provider capture quality is unknown; raw endpoint retained")
                continue
            }
            if [.needsReview, .notApplicable, .unavailable].contains(quality.state) {
                states.append(quality.state); reasons.append(quality.reason); continue
            }
            guard !quality.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  quality.capturedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= marker.occurredAt && $0 <= asOf }) != false else {
                states.append(.needsReview); reasons.append("Provider capture metadata is invalid"); continue
            }
            states.append(quality.capturedAt == nil ? .partial : quality.state)
            reasons.append(quality.reason + (quality.capturedAt == nil ? "; capture time unknown" : ""))
        }
        let state = [DashboardMetricState.needsReview, .notApplicable, .unavailable, .partial].first { states.contains($0) } ?? .available
        return (state, reasons.joined(separator: "; "))
    }
    public func withViewContext(_ description: String) -> Self {
        .init(sessionID: sessionID, treatmentDate: treatmentDate, asOf: asOf, timeZoneID: timeZoneID,
            sourcePolicy: sourcePolicy, filterDescription: filterDescription + "; " + description, markers: markers,
            dose2NotTaken: dose2NotTaken, identityResolved: identityResolved, reviewedProjection: reviewedProjection,
            mainEpisodeIntervals: mainEpisodeIntervals, dosePairSelection: dosePairSelection)
    }
    public enum SelectionError: Error { case invalidEndpoint }
    public func addingSelectedEndpoints(_ endpoints: [DashboardReplayMarker]) throws -> Self {
        let allowed: Set<DashboardReplayMarker.Kind> = [.medicationXR, .medicationIR, .daytimeMedication, .napEnd]
        guard hasValidBoundary, endpoints.allSatisfy({ allowed.contains($0.kind) && $0.sessionID == sessionID && !$0.id.isEmpty &&
            $0.sourceRecordID?.isEmpty == false && $0.occurredAt.timeIntervalSince1970.isFinite && $0.occurredAt <= asOf }),
            Set(endpoints.map(\.id)).count == endpoints.count,
            Set(endpoints.map(\.kind)).count == endpoints.count else { throw SelectionError.invalidEndpoint }
        return .init(sessionID: sessionID, treatmentDate: treatmentDate, asOf: asOf, timeZoneID: timeZoneID,
            sourcePolicy: sourcePolicy, filterDescription: filterDescription + (endpoints.isEmpty ? "" : "; explicit inspection-only endpoint selection"),
            markers: markers.filter { !allowed.contains($0.kind) } + endpoints, dose2NotTaken: dose2NotTaken,
            identityResolved: identityResolved, reviewedProjection: reviewedProjection, mainEpisodeIntervals: mainEpisodeIntervals, dosePairSelection: dosePairSelection)
    }
    public func position(of date: Date, alignment: Alignment) -> Double? {
        guard hasValidBoundary, date.timeIntervalSince1970.isFinite else { return nil }
        if alignment == .clock { return date.timeIntervalSince1970 / 60 }
        let kind: DashboardReplayMarker.Kind = alignment == .dose1 ? .dose1 : .dose2
        let matches = endpoints(for: kind).filter { $0.sessionID == sessionID }
        guard identityResolved, dosePairIsValid, matches.count == 1, let start = matches.first, !start.id.isEmpty,
              start.occurredAt.timeIntervalSince1970.isFinite, start.occurredAt <= asOf else { return nil }
        let minutes = date.timeIntervalSince(start.occurredAt) / 60
        return minutes.isFinite ? minutes : nil
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public var csv: String {
        guard hasValidBoundary else { return "state,reason\nneedsReview,Invalid snapshot identity or time boundary\n" }
        func timestamp(_ date: Date) -> String {
            date.timeIntervalSinceReferenceDate.isFinite ? ISO8601DateFormatter().string(from: date) : "invalid_timestamp"
        }
        var rows = [["field", "value"], ["session_id", sessionID], ["treatment_date", treatmentDate],
                    ["derivation_version", derivationVersion], ["as_of", timestamp(asOf)],
                    ["selected_dose1_id", dosePairSelection?.dose1ID ?? ""], ["selected_dose2_id", dosePairSelection?.dose2ID ?? ""],
                    ["reference_version", "dose_spacing_reference_v1_150_240_minutes"],
                    ["timezone", timeZoneID], ["source_policy", sourcePolicy], ["filters", filterDescription],
                    ["reference", "150–240 minutes built-in reference only; not a prescription or safety range"],
                    ["preset", "minutes", "state", "reason", "start_id", "end_id", "reference_group"]]
        rows += DashboardIntervalPreset.allCases.map { preset in
            let value = interval(preset)
            return [preset.rawValue, value.minutes.map(String.init(describing:)) ?? "", value.state.rawValue,
                    value.reason, value.startID ?? "", value.endID ?? "", value.referenceGroup ?? ""]
        }
        rows += [["main_episode_interval_start", "main_episode_interval_end", "asleep"]]
        rows += mainEpisodeIntervals.map { [timestamp($0.start),
            timestamp($0.end), String($0.asleep)] }
        if let projection = reviewedProjection {
            rows += [["coverage_definition", "Reviewed window; distinct from main-episode total"],
                     ["coverage_start", timestamp(projection.window.start)],
                     ["coverage_end", timestamp(projection.window.end)],
                     ["coverage_version", projection.derivationVersion],
                     ["asleep_minutes", projection.coverage.asleepMinutes.map(String.init(describing:)) ?? ""],
                     ["awake_minutes", projection.coverage.awakeMinutes.map(String.init(describing:)) ?? ""],
                     ["unmeasured_minutes", String(projection.coverage.unmeasuredMinutes)],
                     ["conflict_subset_minutes", String(projection.conflictMinutes)],
                     ["band_start", "band_end", "state"]]
            rows += projection.bands.map { [timestamp($0.start),
                timestamp($0.end), $0.state.rawValue] }
        }
        rows += [["event_id", "kind", "occurred_at", "recorded_at", "source", "source_record_id", "medication_id", "formulation", "actual_amount", "evidence_state", "evidence_reason", "source_captured_at", "provider_record_id"]]
        rows += markers.map { [$0.id, $0.kind.rawValue, timestamp($0.occurredAt),
            $0.recordedAt.map { timestamp($0) } ?? "", $0.source,
            $0.sourceRecordID ?? "", $0.medicationID ?? "", $0.formulation ?? "", $0.amountDescription ?? "",
            $0.evidenceQuality?.state.rawValue ?? ($0.kind.isProviderDerived ? "partial" : "available"),
            $0.evidenceQuality?.reason ?? ($0.kind.isProviderDerived ? "Provider capture quality unknown" : "Local recorded evidence"),
            $0.evidenceQuality?.capturedAt.map(timestamp) ?? "", $0.evidenceQuality?.providerRecordID ?? ""] }
        return rows.map(ReportCSV.row).joined(separator: "\r\n")
    }
}
