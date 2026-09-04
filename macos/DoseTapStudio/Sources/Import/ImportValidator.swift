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
            StudioSessionDateIdentity.key(for: event)
        }
        let sessionKeys = Set(sessions.map { StudioSessionDateIdentity.key(for: $0, events: events) })
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

        if let insightBundle,
           let consent = insightBundle.consent,
           (consent.whoopEnabled || consent.whoopConnected),
           !hasWHOOPSessionSummary(in: insightBundle) {
            globalFlags.append("WHOOP is enabled or connected but no WHOOP session summaries were imported")
        }

        if let insightBundle {
            globalFlags.append(contentsOf: checkInPayloadFlags(in: insightBundle))
        }

        for extraKey in bundleKeys.subtracting(sessionKeys.union(eventKeys)).sorted() {
            append("Supplement exists without base session", to: extraKey, in: &flagsByDate)
        }

        for session in sessions {
            let key = StudioSessionDateIdentity.key(for: session, events: events)
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

    private func append(_ flag: String, to key: String, in storage: inout [String: Set<String>]) {
        storage[key, default: []].insert(flag)
    }

    private func hasWHOOPSessionSummary(in bundle: InsightBundle) -> Bool {
        bundle.sessions.contains { session in
            session.whoop != nil || session.sourceAvailability?.whoop == true
        }
    }

    private func checkInPayloadFlags(in bundle: InsightBundle) -> [String] {
        let preSleepSessions = bundle.sessions.compactMap(\.preSleep)
        let morningSessions = bundle.sessions.compactMap(\.morning)
        let checkInSubmissionCount = bundle.sessions.reduce(0) { total, session in
            total + (session.checkInSubmissions?.count ?? 0)
        }

        var flags: [String] = []

        if !preSleepSessions.isEmpty {
            let missingRawCount = preSleepSessions.filter { ($0.rawAnswersJson ?? "").isEmpty }.count
            if missingRawCount > 0 {
                flags.append("Pre-sleep raw payloads missing: \(missingRawCount) of \(preSleepSessions.count) pre-sleep sessions")
            }
        }

        if !morningSessions.isEmpty {
            flags.append(contentsOf: morningRawPayloadCoverageFlags(bundle.sessions))
        }

        if (!preSleepSessions.isEmpty || !morningSessions.isEmpty) && checkInSubmissionCount == 0 {
            flags.append("No normalized check-in submissions were imported despite pre-sleep or morning summaries")
        }

        return flags
    }

    private func morningRawPayloadCoverageFlags(_ sessions: [InsightSessionSupplement]) -> [String] {
        let morningSessions = sessions.compactMap(\.morning)
        let rawFieldValues: [(String, (InsightMorningSummary) -> String?)] = [
            ("rawPhysicalSymptomsJson", \.rawPhysicalSymptomsJson),
            ("rawRespiratorySymptomsJson", \.rawRespiratorySymptomsJson),
            ("rawSleepTherapyJson", \.rawSleepTherapyJson),
            ("rawSleepEnvironmentJson", \.rawSleepEnvironmentJson),
            ("rawStressContextJson", \.rawStressContextJson),
            ("rawTimingContextJson", \.rawTimingContextJson)
        ]

        let morningSubmissions = sessions
            .flatMap { $0.checkInSubmissions ?? [] }
            .filter { $0.checkInType == "morning" }

        if morningSubmissions.isEmpty {
            let missingFields = rawFieldValues.compactMap { fieldName, read in
                morningSessions.contains { !(read($0) ?? "").isEmpty } ? nil : fieldName
            }
            if missingFields.isEmpty {
                return []
            }
            return ["Morning raw payload fields missing from every session: \(missingFields.joined(separator: ", "))"]
        }

        var expectedSessionDatesByField: [String: Set<String>] = [:]
        var presentSessionDatesByField: [String: Set<String>] = [:]

        for session in sessions {
            if let morning = session.morning {
                for (fieldName, read) in rawFieldValues where !(read(morning) ?? "").isEmpty {
                    presentSessionDatesByField[fieldName, default: []].insert(session.sessionDate)
                }
            }

            for submission in session.checkInSubmissions ?? [] where submission.checkInType == "morning" {
                for fieldName in expectedMorningRawFields(from: submission.responsesJson) {
                    expectedSessionDatesByField[fieldName, default: []].insert(session.sessionDate)
                }
            }
        }

        let coverageIssues = rawFieldValues.compactMap { fieldName, _ -> String? in
            let expectedSessionDates = expectedSessionDatesByField[fieldName] ?? []
            guard !expectedSessionDates.isEmpty else { return nil }

            let presentRequiredSessionDates = (presentSessionDatesByField[fieldName] ?? []).intersection(expectedSessionDates)
            let missingSessionDates = expectedSessionDates.subtracting(presentRequiredSessionDates).sorted()
            guard !missingSessionDates.isEmpty else { return nil }

            return "\(fieldName) \(presentRequiredSessionDates.count)/\(expectedSessionDates.count) missing \(missingSessionDates.joined(separator: ", "))"
        }

        if coverageIssues.isEmpty {
            return []
        }

        return [
            "Morning raw payload coverage is incomplete for required normalized answers: \(coverageIssues.joined(separator: "; "))"
        ]
    }

    private func expectedMorningRawFields(from responsesJson: String) -> [String] {
        guard let data = responsesJson.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var expected = Set<String>()

        if hasTruthyKey("pain.any", in: payload)
            || hasTruthyKey("headache.any", in: payload)
            || hasDetailKey(prefix: "pain.", excluding: ["pain.any"], in: payload)
            || hasDetailKey(prefix: "headache.", excluding: ["headache.any"], in: payload)
            || hasDetailKey(prefix: "soreness.", in: payload)
            || hasDetailKey(prefix: "stiffness.", in: payload)
            || hasTruthyKey("sleep.reflux_burden", in: payload)
            || hasTruthyKey("sleep.restless_legs_burden", in: payload)
            || hasTruthyKey("wake.bathroom_urgency_burden", in: payload) {
            expected.insert("rawPhysicalSymptomsJson")
        }

        if hasTruthyKey("respiratory.any", in: payload)
            || hasDetailKey(prefix: "respiratory.", excluding: ["respiratory.any"], in: payload) {
            expected.insert("rawRespiratorySymptomsJson")
        }

        if hasTruthyKey("sleep_therapy.used", in: payload)
            || hasDetailKey(prefix: "sleep_therapy.", excluding: ["sleep_therapy.used"], in: payload) {
            expected.insert("rawSleepTherapyJson")
        }

        if hasTruthyKey("sleep_environment.any", in: payload)
            || hasDetailKey(prefix: "sleep_environment.", excluding: ["sleep_environment.any"], in: payload) {
            expected.insert("rawSleepEnvironmentJson")
        }

        if hasTruthyKey("overall.stress", in: payload)
            || hasDetailKey(prefix: "morning.stress.", in: payload) {
            expected.insert("rawStressContextJson")
        }

        if payload.contains(where: { key, value in
            ["night.", "wake.", "dose2.", "day_demand."].contains { key.hasPrefix($0) }
                && isTruthy(value)
        }) {
            expected.insert("rawTimingContextJson")
        }

        return Array(expected)
    }

    private func hasTruthyKey(_ key: String, in payload: [String: Any]) -> Bool {
        guard let value = payload[key] else { return false }
        return isTruthy(value)
    }

    private func hasDetailKey(prefix: String, excluding excludedKeys: Set<String> = [], in payload: [String: Any]) -> Bool {
        payload.contains { key, value in
            key.hasPrefix(prefix) && !excludedKeys.contains(key) && isTruthy(value)
        }
    }

    private func isTruthy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let double as Double:
            return double != 0
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !["", "0", "false", "none", "no", "off", "nil", "null"].contains(normalized)
        case is NSNull:
            return false
        default:
            return true
        }
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}
