import Foundation

/// Explicitly selected occurrence endpoints. Recording time is never substituted.
public struct DashboardReplayMarker: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case dose1, dose2, foodFinish, caffeine, returnSleep, deviceSleepEnd, reportedWake, requiredWake
        case medicationXR, medicationIR, daytimeMedication, mainSleepStart, napEnd, reminder, alarmDelivered, event
        public var label: String {
            switch self {
            case .dose1: return "Dose 1"
            case .dose2: return "Dose 2"
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
            }
        }
    }
    public let id: String
    public let sessionID: String
    public let kind: Kind
    public let occurredAt: Date
    public let recordedAt: Date?
    public let source: String
    public init(id: String, sessionID: String, kind: Kind, occurredAt: Date, recordedAt: Date? = nil, source: String) {
        self.id = id; self.sessionID = sessionID; self.kind = kind; self.occurredAt = occurredAt
        self.recordedAt = recordedAt; self.source = source
    }
}

public enum DashboardIntervalPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case dose1ToDose2 = "Dose 1 to Dose 2", foodToDose1 = "Food to Dose 1"
    case dose2ToSleep = "Dose 2 to subsequent observed sleep", dose2ToDeviceEnd = "Dose 2 to device sleep end"
    case dose2ToReportedWake = "Dose 2 to reported final wake", dose2ToRequiredWake = "Dose 2 to required wake"
    case caffeineToDose1 = "Last caffeine to Dose 1", xrToIR = "Selected XR to IR"
    case medicationToSleep = "Daytime medication to main sleep", napToSleep = "Nap end to main sleep"
    case reminderDeviation = "Administration minus saved reminder", deliveredAlarmToDose = "Delivered alarm to administration"
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
    public init(sessionID: String, treatmentDate: String, asOf: Date, timeZoneID: String,
                sourcePolicy: String, filterDescription: String, markers: [DashboardReplayMarker],
                dose2NotTaken: Bool = false, identityResolved: Bool = true,
                reviewedProjection: ReviewedNightSleepProjection? = nil) {
        derivationVersion = "dashboard_replay_v1"; self.sessionID = sessionID; self.treatmentDate = treatmentDate
        self.asOf = asOf; self.timeZoneID = timeZoneID; self.sourcePolicy = sourcePolicy
        self.filterDescription = filterDescription; self.markers = markers.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt
        }
        self.dose2NotTaken = dose2NotTaken; self.identityResolved = identityResolved
        self.reviewedProjection = reviewedProjection
    }
    public func interval(_ preset: DashboardIntervalPreset) -> DashboardIntervalObservation {
        let pair = preset.endpoints
        let starts = markers.filter { $0.kind == pair.0 }, ends = markers.filter { $0.kind == pair.1 }
        func result(_ state: DashboardIntervalObservation.State, _ reason: String, _ value: Double? = nil) -> DashboardIntervalObservation {
            .init(preset: preset, minutes: value, state: state, reason: reason,
                  startID: starts.count == 1 ? starts.first?.id : nil, endID: ends.count == 1 ? ends.first?.id : nil)
        }
        guard identityResolved else { return result(.needsReview, "Session or episode association is unresolved") }
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
        return result(.available, signed ? "Signed elapsed minutes; not a safety classification" : "UTC elapsed minutes; not sleep duration", minutes)
    }
    public func position(of date: Date, alignment: Alignment) -> Double? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        if alignment == .clock { return date.timeIntervalSince1970 / 60 }
        let kind: DashboardReplayMarker.Kind = alignment == .dose1 ? .dose1 : .dose2
        let matches = markers.filter { $0.kind == kind && $0.sessionID == sessionID }
        guard identityResolved, matches.count == 1, let start = matches.first else { return nil }
        return date.timeIntervalSince(start.occurredAt) / 60
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public var csv: String {
        var rows = [["field", "value"], ["session_id", sessionID], ["treatment_date", treatmentDate],
                    ["derivation_version", derivationVersion], ["as_of", ISO8601DateFormatter().string(from: asOf)],
                    ["timezone", timeZoneID], ["source_policy", sourcePolicy], ["filters", filterDescription],
                    ["reference", "150–240 minutes built-in reference only; not a prescription or safety range"],
                    ["preset", "minutes", "state", "reason", "start_id", "end_id", "reference_group"]]
        rows += DashboardIntervalPreset.allCases.map { preset in
            let value = interval(preset)
            return [preset.rawValue, value.minutes.map(String.init(describing:)) ?? "", value.state.rawValue,
                    value.reason, value.startID ?? "", value.endID ?? "", value.referenceGroup ?? ""]
        }
        if let projection = reviewedProjection {
            rows += [["coverage_definition", "Reviewed window; distinct from main-episode total"],
                     ["coverage_start", ISO8601DateFormatter().string(from: projection.window.start)],
                     ["coverage_end", ISO8601DateFormatter().string(from: projection.window.end)],
                     ["coverage_version", projection.derivationVersion],
                     ["asleep_minutes", projection.coverage.asleepMinutes.map(String.init(describing:)) ?? ""],
                     ["awake_minutes", projection.coverage.awakeMinutes.map(String.init(describing:)) ?? ""],
                     ["unmeasured_minutes", String(projection.coverage.unmeasuredMinutes)],
                     ["conflict_subset_minutes", String(projection.conflictMinutes)],
                     ["band_start", "band_end", "state"]]
            rows += projection.bands.map { [ISO8601DateFormatter().string(from: $0.start),
                ISO8601DateFormatter().string(from: $0.end), $0.state.rawValue] }
        }
        rows += [["event_id", "kind", "occurred_at", "recorded_at", "source"]]
        rows += markers.map { [$0.id, $0.kind.rawValue, ISO8601DateFormatter().string(from: $0.occurredAt),
            $0.recordedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "", $0.source] }
        return rows.map(ReportCSV.row).joined(separator: "\r\n")
    }
}
