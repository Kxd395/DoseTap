import Foundation

/// Reporting-only reconciliation. Never repairs source rows or uses current settings.
struct SWDoseReview {
    let outcome: String
    let time: Date?
    let record: SWRecord?
    let evidence: String
}

extension StudioWorkbookData {
    func medicationMetadata(_ record: SWRecord) -> SWObject {
        SW.object(SW.parse(record.fields["details"] ?? record.fields["metadata"]))
    }

    func hasDoseCorrection(_ metadata: SWObject) -> Bool {
        metadata["correction"] != nil && !(metadata["correction"] is NSNull)
    }

    func initialRecording(_ metadata: SWObject) -> Date? {
        hasDoseCorrection(metadata) ? nil : timestamps.parse(metadata["recorded_at_utc"])
    }

    func isRemovedDose(_ record: SWRecord) -> Bool {
        SW.boolean(medicationMetadata(record)["removed_from_effective_record"]) == true
    }

    func reviewedDose(_ group: SWGroup, number: Int) -> SWDoseReview {
        func result(_ outcome: String, _ time: Date? = nil, _ record: SWRecord? = nil, _ evidence: String) -> SWDoseReview {
            SWDoseReview(outcome: outcome, time: time, record: record, evidence: evidence)
        }
        guard group.eligible else { return result("Needs record review", nil, nil, "Identity unresolved; combined values excluded") }
        let events = groupRecords(group, table: "dose_events").filter { !isRemovedDose($0) }
        let taken = events.filter { ["dose\(number)", "dose\(number)_taken"].contains(eventType($0) ?? "") }
        let skipped = number == 2 ? events.filter { ["dose2_skipped", "skip"].contains(eventType($0) ?? "") } : []
        let summary = timestamps.parse(group.original["dose\(number)TimeUTC"])
        if taken.count > 1 || skipped.count > 1 || (!skipped.isEmpty && (!taken.isEmpty || summary != nil)) {
            return result("Conflicting dose records", nil, nil, "Multiple taken/skip records or skip contradicts summary time; inspect Medication Log")
        }
        if let skip = skipped.first { return result("Explicitly skipped", nil, skip, "Explicit source outcome; no administration time") }
        if let record = taken.first {
            guard let time = eventDate(record) else { return result("Taken — time unavailable", nil, record, "Original event has no usable occurrence time") }
            if let summary, abs(summary.timeIntervalSince(time)) > 0.001 {
                return result("Conflicting dose records", nil, nil, "Summary time differs from original event; no timestamp chosen")
            }
            return result("Taken — recorded time available", time, record, hasDoseCorrection(medicationMetadata(record)) ? "Corrected occurrence; original recording time not projected" : "Original occurrence time; precision is only known if explicitly recorded")
        }
        if summary != nil && groupRecords(group, table: "dose_events").contains(where: isRemovedDose) {
            return result("Needs record review", nil, nil, "Removal history contradicts summary-only timing; no administration inferred")
        }
        if let summary { return result("Taken — recorded time available", summary, nil, "Summary timestamp only; original dose row unavailable") }
        return result("Outcome not recorded; regimen state unavailable", nil, nil, "No dose outcome evidence; missing is not skipped")
    }

    func medicationLocal(_ date: Date?) -> WorkbookCell {
        guard let date else { return .blank }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = timezone
        format.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        return .text(format.string(from: date))
    }

    func doseAmount(_ record: SWRecord?) -> Double? {
        record.flatMap { SW.nonnegative(medicationMetadata($0)["amount_mg"]) }
    }

    func doseSummarySheet() -> WorkbookSheet {
        let columns = ["Treatment date", "Dose 1 outcome", "Dose 1 taken (local)", "Dose 2 outcome", "Dose 2 taken (local)",
            "Dose interval", "Timing status", "Dose 1 amount", "Dose 1 unit", "Dose 2 amount", "Dose 2 unit", "Amount status",
            "Dose 2 reminder", "Reminder interval", "Dose 1 recording (local)", "Dose 2 recording (local)",
            "Dose 2 recording delay", "Dose 2 reason", "Dose 2 notes", "Extra dose records", "Dose 1 evidence", "Dose 2 evidence",
            "Local display timezone", "Dose 1 (UTC)", "Dose 2 (UTC)", "Dose interval (minutes)",
            "Date group", "Identity status", "Dose 1 source", "Dose 2 source", "Review medication records", "Dose interval eligibility"]
        let rows = groups.map { group -> [WorkbookCell] in
            let first = reviewedDose(group, number: 1), second = reviewedDose(group, number: 2)
            let m1 = first.record.map(medicationMetadata) ?? [:], m2 = second.record.map(medicationMetadata) ?? [:]
            let a1 = doseAmount(first.record), a2 = doseAmount(second.record)
            let recorded1 = initialRecording(m1), recorded2 = initialRecording(m2)
            let interval = doseInterval(group)
            let timing: String
            if !group.eligible { timing = "Identity unresolved; interval unavailable" }
            else if first.outcome.contains("Conflicting") || second.outcome.contains("Conflicting") { timing = "Conflicting records; interval unavailable" }
            else if let d1 = first.time, let d2 = second.time, d2 <= d1 { timing = "Dose 2 time is at or before Dose 1; review required" }
            else if interval == nil { timing = "Two usable taken times required; interval unavailable" }
            else { timing = "Historical window unavailable; not reclassified" }
            let extra = groupRecords(group, table: "dose_events").filter { eventType($0) == "extra_dose" && !isRemovedDose($0) }.count
            return [SW.text(group.date), .text(first.outcome), medicationLocal(first.time), .text(second.outcome), medicationLocal(second.time),
                SW.duration(interval), .text(timing), SW.numeric(a1), a1 == nil ? .blank : .text("mg"), SW.numeric(a2), a2 == nil ? .blank : .text("mg"),
                .text(a1 != nil && a2 != nil ? "Recorded amounts; no prescription inferred" : "Blank amount means not recorded or not applicable; no historical amount inferred"),
                .text(reminderChoice(m1)), SW.duration(SW.boolean(m1["dose2_reminder_enabled"]) == true ? SW.nonnegative(m1["reminder_interval_minutes"]) : nil),
                medicationLocal(recorded1), medicationLocal(recorded2), SW.duration(recordingDelay(occurred: second.time, recorded: recorded2)),
                SW.text(SW.string(m2["reason"])), SW.text(SW.string(m2["reason_notes"])), group.eligible ? .number(Double(extra)) : .blank,
                .text(first.evidence), .text(second.evidence), .text(timezone.identifier), first.time.map(WorkbookCell.date) ?? .blank,
                second.time.map(WorkbookCell.date) ?? .blank, SW.numeric(interval), .text(group.key), .text(group.identity),
                SW.text(first.record?.key), SW.text(second.record?.key), .link(label: "Open Medication Log; filter treatment date", target: "'Medication Log'!A4"), .text(doseIntervalReason(group))]
        }
        return SW.table("Dose Summary", columns, rows,
            note: "One exported treatment-date group. Interval uses reconciled occurrence times, never alarm or recording times. Blank values remain unavailable, not zero. Reminder target is separate from the medication window. Local times use the export timezone, not a verified historical location. \(timezoneNote)")
    }

    func reminderChoice(_ metadata: SWObject) -> String {
        guard let enabled = SW.boolean(metadata["dose2_reminder_enabled"]) else { return "Not recorded" }
        return enabled ? "Alarm selected" : "No alarm"
    }

    func recordingDelay(occurred: Date?, recorded: Date?) -> Double? {
        guard let occurred, let recorded, recorded >= occurred else { return nil }
        return recorded.timeIntervalSince(occurred) / 60
    }

    func medicationOccurrence(_ record: SWRecord) -> Date? {
        record.table == "medication_events" ? timestamps.parse(record.fields["takenAtUTC"] ?? record.fields["taken_at_utc"]) : eventDate(record)
    }

    func medicationLogSheet() -> WorkbookSheet {
        let columns = ["Treatment dates", "Medicine as recorded", "Dose / record", "Outcome / status", "Amount", "Unit",
            "Occurred (local)", "Recorded (local)", "Recording delay", "Recording evidence", "Time precision", "Entry mode",
            "Source / surface", "Reason", "Notes", "Dose 2 reminder", "Reminder interval", "Recorded early flag", "Recorded late flag",
            "Formulation", "Local display timezone", "Occurred (UTC)", "Recorded (UTC)", "Stored creation (UTC)",
            "Corrected (local)", "Corrected (UTC)", "Identity status", "Session ID", "Source table", "Source record", "Record ID", "Date groups", "Original details"]
        let selected = records.filter { ["dose_events", "medication_events"].contains($0.table) }.sorted {
            if $0.dateSort != $1.dateSort { return $0.dateSort > $1.dateSort }
            let a = medicationOccurrence($0) ?? .distantFuture, b = medicationOccurrence($1) ?? .distantFuture
            return a == b ? $0.key < $1.key : a < b
        }
        let rows = selected.map { record -> [WorkbookCell] in
            let f = record.fields, m = medicationMetadata(record), general = record.table == "medication_events"
            let kind = eventType(record) ?? "Unknown event", removed = isRemovedDose(record)
            let labels = ["dose1": "Dose 1", "dose1_taken": "Dose 1", "dose2": "Dose 2", "dose2_taken": "Dose 2",
                "dose2_skipped": "Dose 2", "skip": "Dose 2", "extra_dose": "Extra dose", "history_correction": "Correction", "snooze": "Snooze"]
            let administration = general || ["dose1", "dose1_taken", "dose2", "dose2_taken", "extra_dose"].contains(kind)
            let occurred = medicationOccurrence(record)
            // General medication creation time is not asserted to be explicit capture time.
            let recorded = initialRecording(m)
            let correctionTime = hasDoseCorrection(m) ? timestamps.parse(SW.object(m["correction"])["corrected_at_utc"] ?? m["recorded_at_utc"]) : nil
            let status: String
            if removed || kind == "history_correction" { status = "Audit only — not an administration" }
            else if ["dose2_skipped", "skip"].contains(kind) { status = "Explicitly skipped" }
            else if administration { status = occurred == nil ? "Taken — time unavailable" : (hasDoseCorrection(m) ? "Taken — corrected record" : "Taken") }
            else { status = "Other event — not an administration" }
            let amount = general ? SW.nonnegative(f["doseMg"] ?? f["dose_mg"]) : SW.nonnegative(m["amount_mg"])
            let unit = general ? SW.string(f["doseUnit"] ?? f["dose_unit"]) : (amount == nil ? nil : "mg")
            let recordingEvidence: String
            if hasDoseCorrection(m) { recordingEvidence = "Correction timestamp is separate; original recording delay unavailable" }
            else if let recorded, let occurred, recorded < occurred { recordingEvidence = "Recording precedes occurrence; delay unavailable" }
            else if recorded != nil { recordingEvidence = "Explicit recorded_at_utc metadata" }
            else { recordingEvidence = "Recording time not captured; stored creation is separate" }
            return [SW.text(record.dateLabel), SW.text(SW.string(f["medicationId"] ?? f["medication_id"] ?? m["medication_id"]) ?? "Not recorded"),
                .text(general ? "Other medication" : labels[kind] ?? kind), .text(status), SW.numeric(amount), SW.text(unit), medicationLocal(occurred),
                medicationLocal(recorded), SW.duration(administration && !removed ? recordingDelay(occurred: occurred, recorded: recorded) : nil),
                .text(recordingEvidence), SW.text(SW.string(m["time_precision"]) ?? "Not recorded"), SW.text(SW.string(m["entry_mode"]) ?? "Not recorded"),
                SW.text(SW.string(m["source"] ?? m["surface"] ?? f["source"]) ?? "Not recorded"), SW.text(SW.string(m["reason"])),
                SW.text(SW.string(m["reason_notes"] ?? f["notes"])), .text(reminderChoice(m)),
                SW.duration(SW.boolean(m["dose2_reminder_enabled"]) == true ? SW.nonnegative(m["reminder_interval_minutes"]) : nil),
                sourceCell(m["is_early"]), sourceCell(m["is_late"]), sourceCell(f["formulation"]), .text(timezone.identifier),
                occurred.map(WorkbookCell.date) ?? .blank, recorded.map(WorkbookCell.date) ?? .blank,
                timestampCell(f["createdAtStoredUTC"] ?? f["created_at"]), medicationLocal(correctionTime), correctionTime.map(WorkbookCell.date) ?? .blank, .text(identity(for: record)), SW.text(record.sessionID),
                .text(record.table), .text(record.key), .text(record.id), SW.text(record.groupKeys.sorted().joined(separator: "; ")),
                sourceCell(f["details"] ?? f["metadata"] ?? f["notes"])]
        }
        return SW.table("Medication Log", columns, rows,
            note: "Canonical doses and separately logged medicines, one original source identity/payload variant per row. Skip, correction and other events are not administrations; identity conflicts remain visible. Blank amount/flags mean unavailable, not zero/false. Recorded timing flags are not a new window classification. Local times use the export timezone. \(timezoneNote)")
    }
}
