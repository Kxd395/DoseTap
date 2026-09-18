import Foundation

extension StudioWorkbookData {
    var detailIdentityColumns: [String] {
        ["Treatment dates", "Date association", "Date groups", "Source record", "Record ID", "Identity status", "Source representation"]
    }
    func detailIdentity(_ record: SWRecord) -> [WorkbookCell] {
        [SW.text(record.dateLabel), .text(record.association), SW.text(record.groupKeys.sorted().joined(separator: "; ")),
         SW.text(record.key), SW.text(record.id), .text(identity(for: record)), .text(record.representation)]
    }
    func recorded(_ record: SWRecord) -> Any? {
        let fields = record.fields
        return fields["created_at_utc"] ?? fields["loggedAtUTC"] ?? fields["timestamp"] ?? fields["submittedAtUTC"]
            ?? fields["submitted_at_utc"] ?? fields["createdAtStoredUTC"] ?? fields["created_at"]
    }
    func expanded(_ fields: SWObject) -> SWObject {
        var result: SWObject = [:]
        func visit(_ value: Any, key: String) {
            if let dict = value as? SWObject, !dict.isEmpty {
                for child in dict.keys.sorted() { visit(dict[child]!, key: key.isEmpty ? child : key + "." + child) }
            } else if let values = value as? [Any], values.allSatisfy({ $0 is String }) {
                result[key] = values.compactMap { $0 as? String }.joined(separator: "; ")
            } else { result[key] = value }
        }
        let names = ["answers_json": "answers", "rawAnswersJson": "answers",
            "physical_symptoms_json": "physical", "rawPhysicalSymptomsJson": "physical",
            "respiratory_symptoms_json": "respiratory", "rawRespiratorySymptomsJson": "respiratory",
            "sleep_environment_json": "environment", "rawSleepEnvironmentJson": "environment",
            "sleep_therapy_json": "therapy", "rawSleepTherapyJson": "therapy",
            "stress_context_json": "stress", "rawStressContextJson": "stress",
            "timing_context_json": "timing", "rawTimingContextJson": "timing",
            "responses_json": "responses", "responsesJson": "responses"]
        for key in fields.keys.sorted() {
            let value = fields[key]!
            if let prefix = names[key], let parsed = SW.parse(value) { visit(parsed, key: prefix) }
            else { visit(value, key: key) }
        }
        return result
    }
    func questionnaireSheet(morning: Bool) -> WorkbookSheet {
        let name = morning ? "Morning" : "Pre-sleep"
        let rows = records(table: morning ? "morning_checkins" : "pre_sleep_logs")
        let fields = rows.map { expanded($0.fields) }
        let priority = morning
            ? ["sleep_quality", "sleepQuality", "feel_rested", "feelRested", "grogginess", "mood", "readiness_for_day"]
            : ["answers.intendedSleepTime", "answers.roomTemp", "answers.noiseLevel", "answers.sleepingSetup.arrangement",
               "answers.sleepingSetup.sharedSpace", "answers.sleepingSetup.pets", "answers.sleepingSetup.location", "answers.bodyPain"]
        let keys = Set(fields.flatMap(\.keys)).sorted {
            let a = priority.firstIndex(of: $0) ?? Int.max, b = priority.firstIndex(of: $1) ?? Int.max
            return a == b ? $0 < $1 : a < b
        }
        let columns = detailIdentityColumns + ["Recorded (UTC)", "Recorded (local)", "Confirmation provenance", "Explicit null fields"] + keys.map { SW.escapedControls($0) }
        let cells = zip(rows, fields).map { record, fields in
            detailIdentity(record) + [timestampCell(recorded(record)), timestamps.localCell(timestamps.parse(recorded(record))),
                .text("Fresh confirmation is not captured for every legacy field; no default is relabeled."),
                SW.text(fields.filter { $0.value is NSNull }.keys.sorted().joined(separator: "; "))]
                + keys.map { sourceCell(fields[$0], key: $0) }
        }
        return SW.table(name, columns, cells, note: "One original questionnaire per source identity and payload variant. \(timezoneNote) Blank cells can mean absent or explicit null; Source Fields preserves the distinction. Nested arrays and long values have full details there. Saved preferences are not nightly confirmations.")
    }

    func eventsSheet() -> WorkbookSheet {
        let selected = records.filter(isOriginalEvent).sorted {
            if $0.dateSort != $1.dateSort { return $0.dateSort > $1.dateSort }
            let a = eventDate($0) ?? .distantFuture, b = eventDate($1) ?? .distantFuture
            return a == b ? $0.key < $1.key : a < b
        }
        let columns = detailIdentityColumns + ["Source table", "Session ID", "Event type", "Occurred (UTC)", "Occurred (local)",
            "Stored creation (UTC)", "Stored creation (local)", "Details", "Source", "Stored occurrence", "Stored creation text", "Device time (source field)"]
        let rows = selected.map { record -> [WorkbookCell] in
            let f = record.fields, time = eventDate(record), recording = timestamps.parse(f["createdAtStoredUTC"] ?? f["created_at"])
            return detailIdentity(record) + [SW.text(record.table), SW.text(record.sessionID), SW.text(eventType(record)),
                time.map(WorkbookCell.date) ?? .blank, timestamps.localCell(time), recording.map(WorkbookCell.date) ?? .blank,
                timestamps.localCell(recording), sourceCell(f["details"] ?? f["notes"] ?? f["metadata"]), sourceCell(f["source"]),
                sourceCell(f["timestampStoredUTC"] ?? f["timestamp"]), sourceCell(f["createdAtStoredUTC"] ?? f["created_at"]), sourceCell(f["deviceTime"])]
        }
        return SW.table("Events", columns, rows, note: "Every original event vocabulary is retained. Normalized copies do not add observations. Occurrence and stored creation are separate; legacy created_at values are not guaranteed capture times. Explicit recording metadata remains in Details and Source Fields. deviceTime is not a verified local timestamp. \(timezoneNote)")
    }
    func isOriginalEvent(_ record: SWRecord) -> Bool { record.representation == "Original event export" || ["dose_events", "sleep_events"].contains(record.table) }
    func eventType(_ record: SWRecord) -> String? { SW.string(record.fields["eventType"] ?? record.fields["event_type"] ?? record.fields["kind"]) }
    func eventDate(_ record: SWRecord) -> Date? { timestamps.parse(record.fields["occurredAtUTC"] ?? record.fields["timestamp"]) }

    func painSheet() -> WorkbookSheet {
        let columns = detailIdentityColumns + ["Assessment", "Recorded (UTC)", "Entry key", "Area", "Side", "Intensity (0–10)",
            "Sensations", "Pattern", "Notes", "Source entry path", "Observation status"]
        var rows: [[WorkbookCell]] = []
        for record in records where ["pre_sleep_logs", "morning_checkins"].contains(record.table) {
            let morning = record.table == "morning_checkins"
            let json = morning ? record.fields["physical_symptoms_json"] ?? record.fields["rawPhysicalSymptomsJson"]
                : record.fields["answers_json"] ?? record.fields["rawAnswersJson"]
            let answers = SW.object(SW.parse(json))
            for (index, entry) in SW.objects(answers["painEntries"]).enumerated() {
                let area = SW.string(entry["area"]), side = SW.string(entry["side"])
                rows.append(detailIdentity(record) + [.text(morning ? "Morning" : "Pre-sleep"), timestampCell(recorded(record)),
                    SW.text([area, side].compactMap { $0 }.joined(separator: "|")), SW.text(area), SW.text(side),
                    sourceCell(entry["intensity"]), SW.text(SW.strings(entry["sensations"])), sourceCell(entry["pattern"]), sourceCell(entry["notes"]),
                    .text("painEntries[\(index)]"), .text("Recorded entry; preferences are separate")])
            }
            // Older aggregate pain remains one aggregate observation, never fabricated back/foot entries.
            if SW.objects(answers["painEntries"]).isEmpty,
               let aggregate = answers[morning ? "painSeverity" : "bodyPain"] ?? record.fields["bodyPain"] {
                rows.append(detailIdentity(record) + [.text(morning ? "Morning" : "Pre-sleep"), timestampCell(recorded(record)),
                    .text("legacy aggregate"), .blank, .blank, morning ? sourceCell(aggregate) : .blank,
                    sourceCell(answers["painType"]), .blank, sourceCell(answers["notes"]), .text(morning ? "painSeverity" : "bodyPain"),
                    SW.text("Legacy aggregate: " + (aggregate as? String ?? SW.canonical(aggregate)) + "; no independent area inferred")])
            }
        }
        return SW.table("Pain", columns, rows, note: "One original questionnaire pain entry. Area and side remain independent; zero is a recorded value. Normalized symptom/answer projections are not counted again. Legacy aggregate pain stays aggregate. Full entry payloads and conflicting variants remain in Source Fields.")
    }

    func daytimeSheet() -> WorkbookSheet {
        let originals = records(table: "checkin_submissions").filter {
            SW.string($0.fields["checkin_type"] ?? $0.fields["checkInType"]) == "night_outcome"
        }
        var items: [(SWRecord, SWObject)] = originals.map { record in
            let payload = SW.object(SW.parse(record.fields["responses_json"] ?? record.fields["responsesJson"]))
            var fields = SW.object(payload["answers"])
            fields["recordedAt"] = payload["recordedAt"]
            return (record, fields)
        }
        for group in groups where !originals.contains(where: { $0.groupKeys.contains(group.key) }) {
            let c = group.collected
            let keys = ["followingDayType", "finalWakeAt", "sleepiness0To10", "sleepinessAssessedAt", "outcomeRecordedAt", "dose2WakeMethod", "backupAlarmSet"]
            guard keys.contains(where: { c[$0] != nil && !(c[$0] is NSNull) }) else { continue }
            let key = group.key + "/collectedNight"
            let record = SWRecord(key: key, baseKey: key, id: "Derived export summary", table: "collectedNight",
                representation: "Summary; original diary row unavailable", payload: c, fields: c, groupKeys: [group.key], dates: [group.date])
            items.append((record, c))
        }
        let expandedItems = items.map { expanded($0.1) }, keys = Set(items.flatMap { expanded($0.1).keys }).sorted()
        let columns = detailIdentityColumns + ["Following day", "Final wake (UTC)", "Sleepiness (0–10)", "Assessed (UTC)", "Recorded (UTC)"] + keys
        let rows = zip(items, expandedItems).map { pair, fields -> [WorkbookCell] in
            let (record, raw) = pair
            return detailIdentity(record) + [sourceCell(raw["dayType"] ?? raw["followingDayType"]), timestampCell(raw["finalWakeAt"]),
                sourceCell(raw["sleepiness"] ?? raw["sleepiness0To10"]), timestampCell(raw["assessedAt"] ?? raw["sleepinessAssessedAt"]),
                timestampCell(raw["recordedAt"] ?? raw["outcomeRecordedAt"])] + keys.map { sourceCell(fields[$0], key: $0) }
        }
        return SW.table("Daytime", columns, rows, note: "One original diary submission. Current answers and earlier revisions are separate; revisions are retained in Source Fields. Timestamped assessments remain timed observations. Future independent assessments require their own original source records. No record means no observation.")
    }

    func sleepMeasuresSheet() -> WorkbookSheet {
        var items: [(SWGroup, String, SWObject)] = []
        for group in groups { for (key, name) in [("healthKit", "Apple Health"), ("whoop", "WHOOP")] {
            let values = SW.object(group.original[key]); if !values.isEmpty { items.append((group, name, values)) }
        } }
        let keys = Set(items.flatMap { $0.2.keys }).subtracting(["recordedIntervals"]).sorted()
        let columns = ["Treatment date", "Date group", "Identity status", "Provider", "Total sleep", "Measurement status", "HRV method"] + keys
        let rows = items.map { group, provider, values in
            [SW.text(group.date), .text(group.key), .text(group.identity), .text(provider), SW.duration(SW.nonnegative(values["totalSleepMinutes"])),
             .text(group.eligible ? "Supplied episode/window estimate; not a 24-hour total" : "Source retained; excluded from combined summaries"),
             .text(provider == "Apple Health" ? "SDNN (ms)" : "RMSSD (ms)")]
            + keys.map { sourceCell(values[$0], key: $0) }
        }
        return SW.table("Sleep Measures", columns, rows, note: "One provider summary per exported date group. Apple Health and WHOOP stay separate. Stage totals are supplied aggregates, not per-interval stage evidence. HRV methods differ. Missing values are blank, never zero-filled.")
    }

    func sleepIntervalsSheet() -> WorkbookSheet {
        let columns = ["Treatment date", "Date group", "Identity status", "Provider", "Interval reference", "Start (UTC)", "End (UTC)",
            "Start (local)", "End (local)", "State", "Duration", "Duration (minutes)", "Event overlaps", "Evidence status"]
        var rows: [[WorkbookCell]] = []
        for group in groups {
            let events = groupRecords(group).filter(isOriginalEvent).compactMap { record -> (String, Date)? in
                eventDate(record).map { (record.key, $0) }
            }
            let intervals = SW.objects(group.health["recordedIntervals"]).enumerated().sorted {
                let a = timestamps.parse($0.element["start"]) ?? .distantFuture, b = timestamps.parse($1.element["start"]) ?? .distantFuture
                return a == b ? $0.offset < $1.offset : a < b
            }
            for (index, interval) in intervals {
                let start = timestamps.parse(interval["start"]), end = timestamps.parse(interval["end"])
                let minutes: Double? = start.flatMap { start in end.flatMap { $0 > start ? $0.timeIntervalSince(start) / 60 : nil } }
                let state = SW.boolean(interval["asleep"]).map { $0 ? "Asleep" : "Awake" } ?? "Unknown"
                let overlaps = events.filter { _, event in
                    guard let start, let end else { return false }; return start <= event && event < end
                }.map(\.0).sorted().joined(separator: "; ")
                rows.append([SW.text(group.date), .text(group.key), .text(group.identity), .text("Apple Health"),
                    .text(group.key + "/healthKit/recordedIntervals[\(index)]"), start.map(WorkbookCell.date) ?? .blank,
                    end.map(WorkbookCell.date) ?? .blank, timestamps.localCell(start), timestamps.localCell(end), .text(state),
                    SW.duration(minutes), SW.numeric(minutes), SW.text(overlaps),
                    .text(minutes == nil ? "Invalid/missing interval bounds; original fields retained" : "Exported interval; stage, sample ID and device not supplied")])
            }
        }
        return SW.table("Sleep Intervals", columns, rows, note: "One exported interval, including overlaps; do not sum overlapping rows as total sleep. Event overlap means shared clock time, not cause or awake duration. Interval references are workbook source paths, not provider sample IDs. \(timezoneNote)")
    }

    func medicationsSheet() -> WorkbookSheet {
        let records = records(table: "medication_events").sorted {
            let a = timestamps.parse($0.fields["takenAtUTC"]) ?? .distantPast, b = timestamps.parse($1.fields["takenAtUTC"]) ?? .distantPast
            return a == b ? $0.key < $1.key : a > b
        }
        let keys = Set(records.flatMap { $0.fields.keys }).sorted()
        return SW.table("Medications", detailIdentityColumns + keys,
            records.map { record in detailIdentity(record) + keys.map { sourceCell(record.fields[$0], key: $0) } },
            note: "One separately logged medication source record. Canonical Dose 1/Dose 2 records remain in Events. Units, formulations, recording timestamps and duplicate confirmation retain their supplied meanings.")
    }
    func inventorySheet() -> WorkbookSheet {
        let records = records(table: "inventory").sorted {
            let a = timestamps.parse($0.fields["as_of_utc"]) ?? .distantPast, b = timestamps.parse($1.fields["as_of_utc"]) ?? .distantPast
            return a == b ? $0.key < $1.key : a > b
        }
        let standard = ["id", "as_of_utc", "medication_name", "bottles_remaining", "doses_remaining", "estimated_days_left", "next_refill_date", "notes", "created_at_stored_utc", "source"]
        let extra = Set(records.flatMap { $0.fields.keys }).subtracting(standard).sorted(), keys = standard + extra
        return SW.table("Inventory", ["Source record"] + keys,
            records.map { record in [SW.text(record.key)] + keys.map { sourceCell(record.fields[$0], key: $0) } },
            note: "One recorded supply snapshot. Estimates and refill values are supplied records, not newly calculated advice. An empty table means no inventory records were exported.")
    }
}
