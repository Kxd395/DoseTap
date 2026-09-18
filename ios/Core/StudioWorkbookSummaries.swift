import Foundation

extension StudioWorkbookData {
    static var sheetNames: [String] { ["Overview", "Nights", "Night Review", "Events", "Pre-sleep", "Morning", "Pain", "Daytime",
        "Sleep Measures", "Sleep Intervals", "Medications", "Inventory", "Source Fields", "Review Issues", "Field Guide"] }

    func overviewSheet() -> WorkbookSheet {
        let columns = ["Period", "Provider", "Population", "Mean sleep", "Median sleep", "Usable measurements", "Period start", "Period end", "Exported date groups",
            "Eligible date groups", "Missing measurements", "Excluded date groups",
            "Mean sleep (minutes)", "Median sleep (minutes)", "Measurement definition", "Explore"]
        let dates = groups.compactMap { timestamps.day($0.date) }, end = dates.max(), first = dates.min()
        let windows: [(String, Int?)] = [("7 days", 7), ("14 days", 14), ("30 days", 30), ("All exported dates", nil)]
        let populations = ["All date groups", "Confirmed following workday", "Confirmed following day off", "Schedule estimate: worklike", "Schedule estimate: offlike"]
        var rows: [[WorkbookCell]] = []
        for (period, length) in windows {
            let start = end.flatMap { end in length.map { end.addingTimeInterval(-Double($0 - 1) * 86_400) } ?? first }
            let range = groups.filter { group in
                guard let date = timestamps.day(group.date), let start, let end else { return false }
                return date >= start && date <= end
            }
            for (providerKey, provider) in [("healthKit", "Apple Health"), ("whoop", "WHOOP")] {
                for population in populations {
                    let matching = range.filter { group in
                        switch population {
                        case "Confirmed following workday": return SW.string(group.collected["followingDayType"]) == "workday"
                        case "Confirmed following day off": return SW.string(group.collected["followingDayType"]) == "dayOff"
                        case "Schedule estimate: worklike": return SW.string(group.context["scheduleDayType"]) == "worklike"
                        case "Schedule estimate: offlike": return SW.string(group.context["scheduleDayType"]) == "offlike"
                        default: return true
                        }
                    }
                    let eligible = matching.filter(\.eligible)
                    let values = eligible.compactMap { SW.nonnegative(SW.object($0.original[providerKey])["totalSleepMinutes"]) }.sorted()
                    let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                    let median: Double? = values.isEmpty ? nil : (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
                    let navigation: WorkbookCell = rows.count < Self.sheetNames.count
                        ? .link(label: Self.sheetNames[rows.count], target: "'\(Self.sheetNames[rows.count])'!A4") : .blank
                    rows.append([.text(period), .text(provider), .text(population), SW.duration(mean), SW.duration(median), .number(Double(values.count)),
                        start.map(WorkbookCell.date) ?? .blank, end.map(WorkbookCell.date) ?? .blank,
                        .number(Double(matching.count)), .number(Double(eligible.count)),
                        .number(Double(eligible.count - values.count)), .number(Double(matching.count - eligible.count)), SW.numeric(mean), SW.numeric(median),
                        .text("Supplied primary-episode sleep; descriptive, not causal or a complete 24-hour total"), navigation])
                }
            }
        }
        var chart: WorkbookChart?
        if let end, let first {
            let chartStart = max(first, end.addingTimeInterval(-29 * 86_400))
            let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyy-MM-dd"
            let grouped = Dictionary(grouping: groups, by: \.date)
            let labels = stride(from: 0, through: Int(end.timeIntervalSince(chartStart) / 86_400), by: 1)
                .map { format.string(from: chartStart.addingTimeInterval(Double($0) * 86_400)) }
            chart = WorkbookChart(title: "Apple Health sleep (minutes), up to 30 calendar days; gaps unavailable/excluded", categories: labels,
                values: labels.map { date in
                    guard let matches = grouped[date], matches.count == 1, let group = matches.first, group.eligible else { return nil }
                    return SW.nonnegative(group.health["totalSleepMinutes"])
                })
        }
        let app = SW.string(root["appVersion"]) ?? "Not supplied", version = SW.string(root["exportVersion"]) ?? "Not supplied"
        let exported = SW.string(root["exportedAtUTC"]) ?? "Not supplied"
        let affected = Set(issues.flatMap { $0.group.components(separatedBy: "; ") }).intersection(Set(groups.map(\.key)))
        let missingCount = allReviewIssues.count - issues.count
        let note = "Fixed snapshot: \(exported). App \(app); Studio export \(version); workbook schema 1. \(timezoneNote) "
            + "\(affected.count) date groups with record-review flags; \(issues.count) record-review issues; \(missingCount) unavailable-provider measurements listed separately. Filters change only their own table. "
            + "Windows end on the latest exported treatment date, including excluded groups. Means use supplied nonnegative measurements, with zero retained. "
            + "Confirmed following-day answers and exported recurring-wake schedule estimates remain separate; schedules are not historical attendance. "
            + "This workbook is a reporting snapshot. Full source evidence remains in the separate Studio bundle; editing Excel never updates the phone."
        return SW.table("Overview", columns, rows, note: note, chart: chart)
    }

    func groupRecords(_ group: SWGroup, table: String? = nil) -> [SWRecord] {
        records.filter { $0.groupKeys.contains(group.key) && (table == nil || $0.table == table!) }
    }
    func doseOutcome(_ group: SWGroup, number: Int) -> String {
        guard group.eligible else { return "Needs record review" }
        let relevant = groupRecords(group, table: "dose_events")
        let taken = relevant.filter { ["dose\(number)", "dose\(number)_taken"].contains(eventType($0) ?? "") }
        let skipped = number == 2 ? relevant.filter { ["dose2_skipped", "skip"].contains(eventType($0) ?? "") } : []
        if taken.count > 1 || skipped.count > 1 || (!taken.isEmpty && !skipped.isEmpty) { return "Conflicting dose records" }
        if !skipped.isEmpty { return "Explicitly skipped" }
        if timestamps.parse(group.original["dose\(number)TimeUTC"]) != nil { return "Taken — recorded time available" }
        if !taken.isEmpty { return "Taken — time unavailable" }
        return "Outcome not recorded; regimen state unavailable"
    }
    func doseTime(_ group: SWGroup, number: Int) -> Date? {
        guard group.eligible, !doseOutcome(group, number: number).contains("Conflicting") else { return nil }
        return timestamps.parse(group.original["dose\(number)TimeUTC"])
    }
    func doseInterval(_ group: SWGroup) -> Double? {
        guard let first = doseTime(group, number: 1), let second = doseTime(group, number: 2), second >= first else { return nil }
        return second.timeIntervalSince(first) / 60
    }
    func nightsSheet() -> WorkbookSheet {
        let columns = ["Treatment date", "Date group", "Identity status", "Included in summaries", "Review reasons", "Session IDs",
            "Dose 1 outcome", "Dose 1 (UTC)", "Dose 1 (local)", "Dose 2 outcome", "Dose 2 (UTC)", "Dose 2 (local)",
            "Dose interval", "Dose interval (minutes)", "Dose window classification", "Apple Health sleep", "WHOOP sleep",
            "Following day (recorded)", "Schedule estimate", "Recorded night type", "First night off (recorded)",
            "Pre-sleep records", "Morning records", "Event records", "Sleepiness (0–10)", "Sleepiness assessment (UTC)", "Review this date"]
        let rows = groups.map { group -> [WorkbookCell] in
            let d1 = doseTime(group, number: 1), d2 = doseTime(group, number: 2), interval = doseInterval(group)
            let identity = SW.object(group.original["identityResolution"])
            let eventCount = groupRecords(group).filter { $0.representation == "Original event export" || ["dose_events", "sleep_events"].contains($0.table) }.count
            return [SW.text(group.date), .text(group.key), .text(group.identity), .text(group.eligible ? "Yes" : "No"),
                SW.text(Array(Set(group.issues)).sorted().joined(separator: "; ")), SW.text(SW.strings(identity["sessionIds"])),
                .text(doseOutcome(group, number: 1)), d1.map(WorkbookCell.date) ?? .blank, timestamps.localCell(d1),
                .text(doseOutcome(group, number: 2)), d2.map(WorkbookCell.date) ?? .blank, timestamps.localCell(d2),
                SW.duration(interval), SW.numeric(interval), .text("Historical configured window not exported; not reclassified"),
                SW.duration(group.eligible ? SW.nonnegative(group.health["totalSleepMinutes"]) : nil),
                SW.duration(group.eligible ? SW.nonnegative(SW.object(group.original["whoop"])["totalSleepMinutes"]) : nil),
                group.eligible ? sourceCell(group.collected["followingDayType"]) : .blank,
                group.eligible ? sourceCell(group.context["scheduleDayType"]) : .blank,
                group.eligible ? sourceCell(group.context["explicitNightType"]) : .blank,
                group.eligible ? sourceCell(group.context["firstNightOffAfterWorkBlock"]) : .blank,
                .number(Double(groupRecords(group, table: "pre_sleep_logs").count)),
                .number(Double(groupRecords(group, table: "morning_checkins").count)), .number(Double(eventCount)),
                group.eligible ? sourceCell(group.collected["sleepiness0To10"]) : .blank,
                group.eligible ? timestampCell(group.collected["sleepinessAssessedAt"]) : .blank,
                .link(label: "Open Night Review; filter this date/group", target: "'Night Review'!A4")]
        }
        return SW.table("Nights", columns, rows, note: "One exported treatment-date group. Unresolved groups remain visible, with combined values excluded. Source records stay in detail sheets. Links open the sheet header; filter by Treatment date and Date group so sorting cannot change record identity. Coverage counts describe records, never whether a dose was taken. \(timezoneNote)")
    }

    func reviewIssuesSheet() -> WorkbookSheet {
        let columns = ["Treatment date", "Date group", "Category", "Reason", "Source record", "Action"]
        let rows = allReviewIssues.map { issue in [SW.text(issue.date), SW.text(issue.group), SW.text(issue.category), SW.text(issue.reason),
            SW.text(issue.source), .text(issue.category == "Unavailable measurement"
                ? "Availability is not proof of complete coverage or read permission; missing values do not enter averages"
                : "Inspect source evidence; no source records were repaired or changed")] }
        return SW.table("Review Issues", columns, rows, note: "One issue can affect several dates; one date can have several issues. Unavailable provider measurements are listed separately from record-review flags, and provider absence is not necessarily a defect. Missing data does not mean zero or a skipped dose. Make corrections in the app and export again.")
    }
    var allReviewIssues: [SWIssue] {
        var result = issues
        for group in groups {
            for (key, provider) in [("healthKit", "Apple Health"), ("whoop", "WHOOP")] where SW.nonnegative(SW.object(group.original[key])["totalSleepMinutes"]) == nil {
                result.append(SWIssue(group: group.key, date: group.date, category: "Unavailable measurement",
                    reason: "\(provider) total sleep is absent or unusable; it contributes no value to an average.", source: group.key + "/" + key))
            }
        }
        return result
    }
}
