import Foundation

extension StudioWorkbookData {
    func doseIntervalReason(_ group: SWGroup) -> String {
        guard group.eligible else { return "identity_unresolved" }
        let first = reviewedDose(group, number: 1), second = reviewedDose(group, number: 2)
        if [first, second].contains(where: { $0.outcome.contains("Conflicting") || $0.outcome == "Needs record review" }) {
            return "conflicting_dose_records"
        }
        if second.outcome == "Explicitly skipped" { return "dose2_explicitly_skipped" }
        guard let a = first.time, let b = second.time else { return "missing_dose_time" }
        return b <= a ? "nonpositive_dose_interval" : "available"
    }

    func doseTimingReview(_ group: SWGroup) -> SWObject {
        let reason = doseIntervalReason(group)
        let status = reason == "available" ? "available" : (["missing_dose_time", "dose2_explicitly_skipped"].contains(reason) ? "missing" : "needs_review")
        var result: SWObject = ["version": 1, "status": status, "reason": reason,
                               "derivationVersion": "recorded_dose_spacing_v1"]
        if let first = doseTime(group, number: 1), let second = doseTime(group, number: 2) {
            result["rawIntervalSeconds"] = second.timeIntervalSince(first)
            if reason == "available" { result["intervalSeconds"] = second.timeIntervalSince(first) }
        }
        return result
    }
}

/// Produces both reporting artifacts from the same finalized source selection.
/// No medication, settings, storage or provider access. Original source payloads are retained.
public enum StudioDoseTimingExport {
    public static func prepare(bundleData: Data) throws -> (bundleData: Data, sessionsCSV: String) {
        let data = try StudioWorkbookData(bundleData: bundleData, inventoryCSV: "")
        guard (data.root["schemaVersion"] as? Int).map({ $0 >= 3 }) == true else {
            throw StudioWorkbookProjectionError.unsupportedBundle
        }
        var root = data.root
        root["schemaVersion"] = 4
        root["exportVersion"] = "2.9"
        root["dateGroups"] = data.groups.map { group -> SWObject in
            var row = group.original
            row["doseTimingReview"] = data.doseTimingReview(group)
            return row
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func time(_ value: Date?) -> String { value.map(formatter.string(from:)) ?? "" }
        func number(_ value: Any?) -> String { SW.number(value).map { String($0) } ?? "" }
        let header = "started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes,session_date,session_id,actual_interval_seconds,interval_status,interval_review_reason,historical_window_status,dose2_reminder_enabled,reminder_interval_minutes"
        var rows = [header]
        for group in data.groups where group.eligible {
            let first = data.reviewedDose(group, number: 1), second = data.reviewedDose(group, number: 2)
            guard let start = first.time else { continue } // legacy CSV requires Dose 1; JSON retains all groups
            let review = data.doseTimingReview(group), reason = data.doseIntervalReason(group)
            let metadata = first.record.map(data.medicationMetadata) ?? [:]
            let reminder = SW.boolean(metadata["dose2_reminder_enabled"])
            let whoop = SW.object(group.original["whoop"])
            let outcome = review["status"] as? String == "needs_review" ? "needs_review"
                : second.outcome == "Explicitly skipped" ? "explicitly_skipped" : second.time == nil ? "missing" : "taken"
            let fields: [String] = [time(start), time(second.time), "", data.doseInterval(group).map { String(Int($0)) } ?? "", outcome,
                          SW.number(whoop["recoveryScore"]).map { String(Int($0.rounded())) } ?? "",
                          number(group.health["averageHeartRate"]), number(whoop["sleepEfficiency"]), "",
                          group.date, SW.strings(SW.object(group.original["identityResolution"])["sessionIds"]) ?? "",
                          number(review["intervalSeconds"]), review["status"] as? String ?? "", reason, "unavailable",
                          reminder.map { $0 ? "true" : "false" } ?? "",
                          reminder == true ? number(metadata["reminder_interval_minutes"]) : ""]
            rows.append(fields.map(ReportCSV.field).joined(separator: ","))
        }
        return (try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]), rows.joined(separator: "\n") + "\n")
    }
}
