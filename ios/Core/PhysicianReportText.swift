import Foundation

public extension PhysicianReportSnapshot {
    /// The printable companion to the frozen preview; no independent derivation.
    var reviewText: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: period.timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        func date(_ value: Date) -> String { formatter.string(from: value) }
        func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "unavailable" }
        func summary(_ value: PhysicianMetricSummary) -> String {
            "\(value.month.map { $0 + " • " } ?? "")\(value.metricID): median \(number(value.median)) \(value.unit); middle 50% \(number(value.lowerQuartile))–\(number(value.upperQuartile))\n" +
            "\(value.availableCount)/\(value.eligibleCount) eligible observations available; \(value.assessedDays)/\(value.calendarDayCount) assessed days; \(value.availableDays) days with values. Partial \(value.partialCount); unavailable \(value.unavailableCount); review \(value.reviewCount); not applicable \(value.notApplicableCount); not collected \(value.notCollectedCount); unplaced \(value.unplacedCount).\n" +
            "Source: \(value.source); definition: \(value.definitionVersion)."
        }
        func observation(_ value: PhysicianReportObservation) -> String {
            "\(value.observedAt.map(date) ?? "Unknown occurrence time") • \(value.metricID): \(number(value.value)) \(value.unit) [\(value.state.label)]\n" +
            "\(value.detail)\nSource: \(value.source); definition: \(value.definitionVersion); record IDs: \(value.recordIDs.joined(separator: ", "))."
        }
        let noteText = notes.map { note in
            "\(note.activity) [\(note.opportunity.label)]\n\(note.comment)\nReviewed: \(date(note.reviewedAt)); linked examples: \(note.evidenceIDs.joined(separator: ", "))."
        }.joined(separator: "\n\n")
        let reviewRows = observations.filter { $0.requiresReview || $0.state == .needsReview || $0.observedAt == nil }
        var sections: [String] = []
        sections.append("DOSETAP • PHYSICIAN REVIEW")
        sections.append("\(period.label): \(date(period.start)) to \(date(period.endExclusive)) (end exclusive).\n\(period.calendarDayCount) calendar days. Timezone: \(period.timeZoneIdentifier). Captured: \(date(generatedAt)).")
        sections.append("Snapshot: \(id.uuidString)\n\(version); \(period.version); DoseTap \(appVersion).\n\(coverageDescription)")
        sections.append("Patient-recorded/provider observations for discussion. No diagnosis, treatment recommendation, driving clearance or derived clinical-scale score. Missing information is not zero. Unknown-time records are unplaced and may be outside this period.")
        sections.append("FULL-PERIOD OVERVIEW\n" + (summaries.isEmpty ? "No observations in this period." : summaries.map(summary).joined(separator: "\n\n")))
        sections.append("MONTHLY DETAIL\n" + monthlySummaries.map(summary).joined(separator: "\n\n"))
        sections.append("RECENT 28-DAY DETAIL (alongside full period)\n" + recentDetail(days: 28).map(observation).joined(separator: "\n\n"))
        sections.append("UNSCORED VISIT NOTES\n" + noteText)
        sections.append("VISIT QUESTIONS\n" + questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n"))
        sections.append("REVIEW APPENDIX\nSerious, ambiguous and unknown-time observations retained for review.\n" + reviewRows.map(observation).joined(separator: "\n\n"))
        sections.append("The companion JSON preserves the entire snapshot. The detail CSV preserves all selected source observations with formula-safe reversible text. Later corrections require a new preview.")
        return sections.joined(separator: "\n\n")
    }
}
