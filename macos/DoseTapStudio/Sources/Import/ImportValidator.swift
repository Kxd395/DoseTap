import Foundation

struct ImportValidationReport: Equatable {
    let globalFlags: [String]
    let sessionFlagsByDate: [String: [String]]

    static let empty = ImportValidationReport(globalFlags: [], sessionFlagsByDate: [:])

    var affectedSessionCount: Int {
        sessionFlagsByDate.count
    }

    var sessionFlagCount: Int {
        sessionFlagsByDate.values.reduce(0) { $0 + $1.count }
    }

    var totalIssueCount: Int {
        globalFlags.count + sessionFlagCount
    }

    var hasIssues: Bool {
        totalIssueCount > 0
    }
}

struct ImportValidator {
    func validate(
        sessions: [DoseSession],
        events: [DoseEvent],
        insightBundle: InsightBundle?
    ) -> ImportValidationReport {
        let groupedEvents = Dictionary(grouping: events) { event in
            sessionKey(for: event.occurredAtUTC)
        }
        let sessionKeys = Set(sessions.map { sessionKey(for: $0.startedUTC) })
        let eventKeys = Set(groupedEvents.keys)
        let bundleKeys = Set(insightBundle?.sessions.map(\.sessionDate) ?? [])

        var globalFlags: [String] = []
        var flagsByDate: [String: Set<String>] = [:]

        if let insightBundle, insightBundle.sessions.count != sessions.count {
            globalFlags.append(
                "Session count mismatch: sessions.csv has \(sessions.count), insights bundle has \(insightBundle.sessions.count)"
            )
        }

        if let exportWarnings = insightBundle?.exportWarnings {
            globalFlags.append(contentsOf: exportWarnings)
        }

        for extraKey in bundleKeys.subtracting(sessionKeys.union(eventKeys)).sorted() {
            append("Supplement exists without base session", to: extraKey, in: &flagsByDate)
        }

        for session in sessions {
            let key = sessionKey(for: session.startedUTC)
            let sessionEvents: [DoseEvent] = (groupedEvents[key] ?? []).sorted { lhs, rhs in
                lhs.occurredAtUTC < rhs.occurredAtUTC
            }

            if let endedUTC = session.endedUTC, endedUTC < session.startedUTC {
                append("Session ended before it started", to: key, in: &flagsByDate)
            }

            if let interval = session.windowActualMin {
                if interval < 0 {
                    append("Impossible negative interval", to: key, in: &flagsByDate)
                } else if interval > 360 {
                    append("Extreme interval exceeds 360 minutes", to: key, in: &flagsByDate)
                }
            }

            let dose1Events = sessionEvents.filter { $0.eventType == .dose1_taken }
            let dose2Events = sessionEvents.filter { $0.eventType == .dose2_taken }
            let skippedEvents = sessionEvents.filter { $0.eventType == .dose2_skipped }
            let lightsOutEvents = sessionEvents.filter { $0.eventType == .lights_out }
            let wakeFinalEvents = sessionEvents.filter { $0.eventType == .wake_final }

            if lightsOutEvents.count > 1 {
                append("Duplicate lights-out logs", to: key, in: &flagsByDate)
            }

            if wakeFinalEvents.count > 1 {
                append("Duplicate wake-final logs", to: key, in: &flagsByDate)
            }

            if session.adherenceFlag == "ok" && dose2Events.isEmpty && skippedEvents.isEmpty {
                append("Session marked ok but Dose 2 outcome is missing", to: key, in: &flagsByDate)
            }

            if !skippedEvents.isEmpty && !dose2Events.isEmpty {
                append("Conflicting Dose 2 taken and skipped events", to: key, in: &flagsByDate)
            }

            if let dose1Time = dose1Events.first?.occurredAtUTC,
               let dose2Time = dose2Events.first?.occurredAtUTC {
                let eventInterval = Int(dose2Time.timeIntervalSince(dose1Time) / 60)

                if eventInterval < 0 {
                    append("Dose 2 event occurs before Dose 1", to: key, in: &flagsByDate)
                }

                if let sessionInterval = session.windowActualMin,
                   abs(eventInterval - sessionInterval) > 5 {
                    append("Session interval mismatches event timeline", to: key, in: &flagsByDate)
                }
            }
        }

        let sessionFlagsByDate = flagsByDate.mapValues { Array($0).sorted() }
        return ImportValidationReport(
            globalFlags: Array(Set(globalFlags)).sorted(),
            sessionFlagsByDate: sessionFlagsByDate
        )
    }

    private func sessionKey(for date: Date) -> String {
        Self.sessionDateFormatter.string(from: date)
    }

    private func append(_ flag: String, to key: String, in storage: inout [String: Set<String>]) {
        storage[key, default: []].insert(flag)
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}
