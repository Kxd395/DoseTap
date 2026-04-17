import Foundation

enum InsightNightTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Nights"
    case work = "Work Nights"
    case off = "Off Nights"
    case transition = "Transitions"
    case weekend = "Weekend"
    case weekday = "Weekday"

    var id: String { rawValue }
}

enum InsightWakeTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Wake Types"
    case natural = "Natural Wake"
    case alarm = "Alarm Wake"
    case mixed = "Mixed / External"
    case unknown = "Unknown Wake"

    var id: String { rawValue }
}

enum InsightScheduleFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Schedules"
    case worklike = "Worklike"
    case offlike = "Offlike"
    case transition = "Transition"
    case uniform = "Uniform"
    case highDemand = "High Demand"

    var id: String { rawValue }
}

struct InsightAvailabilityRow: Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let availableCount: Int
    let totalCount: Int

    var id: String { key }

    var missingCount: Int {
        max(0, totalCount - availableCount)
    }

    var coverageRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(availableCount) / Double(totalCount)
    }

    var coveragePercentText: String {
        String(format: "%.0f%%", coverageRatio * 100.0)
    }
}

enum InsightRecommendationReadiness: String, Hashable, Sendable {
    case ready = "Ready"
    case caution = "Use Caution"
    case limited = "Limited Evidence"

    var description: String {
        switch self {
        case .ready:
            return "Coverage is broad enough to review recommendation cohorts with reasonable trust."
        case .caution:
            return "Recommendations are usable, but missing data or import flags still reduce confidence."
        case .limited:
            return "The evidence base is too thin to rely on timing guidance yet."
        }
    }
}

struct InsightCoverageSummary: Hashable, Sendable {
    let totalNights: Int
    let flaggedNights: Int
    let importIssueNights: Int
    let exclusionNights: Int
    let trainableNights: Int
    let missingMorningNights: Int
    let missingPreSleepNights: Int
    let missingWearableNights: Int
    let naturalWakeNights: Int
    let alarmWakeNights: Int
    let workNights: Int
    let offNights: Int
    let transitionNights: Int
    let workSafetyContextNights: Int
    let clinicalContextNights: Int
    let sleepTherapyNights: Int
    let fastMetabolizerReferenceNights: Int
    let rows: [InsightAvailabilityRow]

    init(sessions: [InsightSession], validationReport: ImportValidationReport = .empty) {
        totalNights = sessions.count
        flaggedNights = sessions.filter { !$0.qualityFlags.isEmpty }.count
        importIssueNights = validationReport.affectedSessionCount
        exclusionNights = sessions.filter { !$0.classification.exclusionReasons.isEmpty }.count
        trainableNights = sessions.filter(\.countsTowardRecommendationTraining).count
        missingMorningNights = sessions.filter { $0.morning == nil }.count
        missingPreSleepNights = sessions.filter { $0.preSleep == nil }.count
        missingWearableNights = sessions.filter { $0.healthKit == nil && $0.whoop == nil }.count
        naturalWakeNights = sessions.filter { $0.nightWakeFilter == .natural }.count
        alarmWakeNights = sessions.filter { $0.nightWakeFilter == .alarm }.count
        workNights = sessions.filter { $0.nightTypeFilter == .work }.count
        offNights = sessions.filter { $0.nightTypeFilter == .off }.count
        transitionNights = sessions.filter { $0.nightTypeFilter == .transition }.count
        workSafetyContextNights = sessions.filter(\.hasWorkSafetyContext).count
        clinicalContextNights = sessions.filter(\.hasClinicalContext).count
        sleepTherapyNights = sessions.filter(\.hasSleepTherapyContext).count
        fastMetabolizerReferenceNights = sessions.filter(\.hasFastMetabolizerReference).count

        rows = [
            Self.makeRow(key: "dose_events", title: "Dose events", sessions: sessions) { $0.sourceAvailability?.doseEvents == true || !$0.events.isEmpty },
            Self.makeRow(key: "pre_sleep", title: "Pre-sleep logs", sessions: sessions) { $0.preSleep != nil },
            Self.makeRow(key: "morning", title: "Morning check-ins", sessions: sessions) { $0.morning != nil },
            Self.makeRow(key: "apple_health", title: "Apple Health", sessions: sessions) { $0.healthKit != nil },
            Self.makeRow(key: "whoop", title: "WHOOP", sessions: sessions) { $0.whoop != nil },
            Self.makeRow(key: "alarm", title: "Alarm diagnostics", sessions: sessions) { $0.sourceAvailability?.alarmDiagnostics == true },
            Self.makeRow(key: "raw_events", title: "Raw events", sessions: sessions) { !$0.rawEvents.isEmpty },
            Self.makeRow(key: "normalized_events", title: "Normalized events", sessions: sessions) { !$0.normalizedEvents.isEmpty },
            Self.makeRow(key: "provenance", title: "Metric provenance", sessions: sessions) { !$0.metricProvenance.isEmpty },
            Self.makeRow(key: "work_safety_context", title: "Work / safety context", sessions: sessions) { $0.hasWorkSafetyContext },
            Self.makeRow(key: "clinical_context", title: "Clinical context", sessions: sessions) { $0.hasClinicalContext },
            Self.makeRow(key: "sleep_therapy", title: "Sleep therapy", sessions: sessions) { $0.hasSleepTherapyContext },
            Self.makeRow(key: "fast_metabolizer", title: "Fast-metabolizer reference", sessions: sessions) { $0.hasFastMetabolizerReference },
            Self.makeRow(key: "trainable", title: "Trainable nights", sessions: sessions) { $0.countsTowardRecommendationTraining }
        ]
    }

    var readiness: InsightRecommendationReadiness {
        guard totalNights > 0, trainableNights >= 2 else {
            return .limited
        }

        let morningCoverage = rowValue(for: "morning")?.coverageRatio ?? 0
        let wearableCoverage = max(
            rowValue(for: "apple_health")?.coverageRatio ?? 0,
            rowValue(for: "whoop")?.coverageRatio ?? 0
        )

        if trainableNights >= 8 && importIssueNights == 0 && morningCoverage >= 0.65 && wearableCoverage >= 0.4 {
            return .ready
        }

        return .caution
    }

    var readinessSummary: String {
        "\(readiness.rawValue): \(readiness.description)"
    }

    private func rowValue(for key: String) -> InsightAvailabilityRow? {
        rows.first(where: { $0.key == key })
    }

    private static func makeRow(
        key: String,
        title: String,
        sessions: [InsightSession],
        predicate: (InsightSession) -> Bool
    ) -> InsightAvailabilityRow {
        InsightAvailabilityRow(
            key: key,
            title: title,
            availableCount: sessions.filter(predicate).count,
            totalCount: sessions.count
        )
    }
}

extension InsightSession {
    var nightTypeFilter: InsightNightTypeFilter {
        let tags = classification.tags
        if tags.contains(.transitionIntoWorkBlock) || tags.contains(.transitionOutOfWorkBlock) {
            return .transition
        }
        if tags.contains(.workNight) {
            return .work
        }
        if tags.contains(.offNight) {
            return .off
        }
        if tags.contains(.weekendNight) {
            return .weekend
        }
        return .weekday
    }

    var nightWakeFilter: InsightWakeTypeFilter {
        switch normalizedFilterValue(context?.explicitWakeType) ?? normalizedFilterValue(context?.wakeSignal) {
        case "natural", "likely_natural":
            return .natural
        case "alarm", "alarm_then_snooze", "alarm_assisted":
            return .alarm
        case "mixed", "external_interrupt":
            return .mixed
        default:
            return .unknown
        }
    }

    var scheduleFilter: InsightScheduleFilter {
        if nightTypeFilter == .transition {
            return .transition
        }
        if classification.tags.contains(.highDemandNextDay) {
            return .highDemand
        }

        switch normalizedFilterValue(context?.scheduleDayType) {
        case "worklike":
            return .worklike
        case "offlike":
            return .offlike
        default:
            return .uniform
        }
    }

    var sourceBadgeText: String {
        let sources = sourceAvailabilitySummary
        guard !sources.isEmpty else { return "—" }
        return sources.joined(separator: ", ")
    }

    func matches(filters: InsightFilterState) -> Bool {
        if filters.lateDoseOnly && !isLateDose2 {
            return false
        }
        if filters.skippedOnly && !dose2Skipped {
            return false
        }
        if filters.qualityIssuesOnly && qualityFlags.isEmpty {
            return false
        }
        if filters.trainableOnly && !countsTowardRecommendationTraining {
            return false
        }
        if filters.workSafetyContextOnly && !hasWorkSafetyContext {
            return false
        }
        if filters.clinicalContextOnly && !hasClinicalContext {
            return false
        }
        if filters.nightType != .all && nightTypeFilter != filters.nightType {
            return false
        }
        if filters.wakeType != .all && nightWakeFilter != filters.wakeType {
            return false
        }
        if filters.schedule != .all && scheduleFilter != filters.schedule {
            return false
        }

        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystack = [
            sessionDate,
            notes ?? "",
            qualitySummary,
            adherenceFlag ?? "",
            comparableCohortKey,
            explicitNightTypeLabel ?? "",
            explicitNextDayDemandLabel ?? "",
            sourceBadgeText
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query.lowercased())
    }

    private func normalizedFilterValue(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
