import Foundation
import DoseCore

/// Frozen view inputs and derived values, including exact endpoint coverage and historical target sources.
struct ReplayInspectionExport: Codable {
    struct Row: Codable {
        let observationID: String
        let snapshot: DashboardReplaySnapshot
        let recordedWakeTarget: DashboardRecordedWakeTarget
        let postDoseCoverage: [DashboardPostDoseCoverage]
        init(observationID: String, snapshot: DashboardReplaySnapshot, recordedWakeTarget: DashboardRecordedWakeTarget) {
            self.observationID = observationID; self.snapshot = snapshot; self.recordedWakeTarget = recordedWakeTarget
            postDoseCoverage = [.dose2ToDeviceEnd, .dose2ToReportedWake, .dose2ToRequiredWake].map {
                DashboardPostDoseCoverage.calculate(snapshot: snapshot, preset: $0)
            }
        }
    }
    private(set) var version = "dashboard_inspection_export_v1"
    let scope: String
    let selectedObservationID: String?
    let rows: [Row]
    func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    var csv: String {
        var sections = [ReportCSV.row(["export_version", version]), ReportCSV.row(["scope", scope]),
                        ReportCSV.row(["selected_observation_id", selectedObservationID ?? ""])]
        func number(_ value: Double?) -> String { value.map(String.init(describing:)) ?? "" }
        func timestamp(_ value: Date) -> String { value.timeIntervalSinceReferenceDate.isFinite ? ISO8601DateFormatter().string(from: value) : "invalid_timestamp" }
        for row in rows {
            sections += [ReportCSV.row(["observation_id", row.observationID]), row.snapshot.csv,
                ReportCSV.row(["required_wake_state", row.recordedWakeTarget.state.rawValue, row.recordedWakeTarget.reason]),
                ReportCSV.row(["wake_source_event_id", "event_session_id", "warning_session_id", "revision", "required_wake", "timezone"])]
            sections += row.recordedWakeTarget.sources.map {
                ReportCSV.row([$0.eventID, $0.eventSessionID ?? "", $0.sessionID, $0.revision.uuidString, timestamp($0.requiredWake), $0.timeZoneID])
            }
            sections.append(ReportCSV.row(["postdose_endpoint", "state", "elapsed_minutes", "asleep_minutes", "awake_minutes", "unmeasured_minutes", "conflict_subset_minutes", "start_id", "end_id", "reason"]))
            sections += row.postDoseCoverage.map {
                ReportCSV.row([$0.preset.rawValue, $0.state.rawValue, number($0.elapsedMinutes), number($0.asleepMinutes),
                    number($0.awakeMinutes), number($0.unmeasuredMinutes), number($0.conflictMinutes), $0.startID ?? "", $0.endID ?? "", $0.reason])
            }
        }
        return sections.joined(separator: "\n") + "\n"
    }
}
