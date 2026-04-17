import Foundation

struct InsightSessionBuilder {
    func build(
        sessions: [DoseSession],
        events: [DoseEvent],
        supplementsBySessionDate: [String: InsightSessionSupplement] = [:],
        validationFlagsBySessionDate: [String: [String]] = [:]
    ) -> [InsightSession] {
        var sessionsByNight: [String: DoseSession] = [:]
        for session in sessions {
            sessionsByNight[sessionKey(for: session.startedUTC)] = session
        }

        let groupedEvents = Dictionary(grouping: events) { event in
            sessionKey(for: event.occurredAtUTC)
        }

        let allKeys = Set(sessionsByNight.keys).union(groupedEvents.keys)
        return allKeys.compactMap { key in
            buildSession(
                key: key,
                session: sessionsByNight[key],
                events: groupedEvents[key] ?? [],
                supplement: supplementsBySessionDate[key],
                validationFlags: validationFlagsBySessionDate[key] ?? []
            )
        }
        .sorted { $0.sessionDate > $1.sessionDate }
    }

    private func buildSession(
        key: String,
        session: DoseSession?,
        events: [DoseEvent],
        supplement: InsightSessionSupplement?,
        validationFlags: [String]
    ) -> InsightSession? {
        let sortedEvents = events.sorted { $0.occurredAtUTC < $1.occurredAtUTC }
        let mappedEvents = sortedEvents.map {
            InsightEvent(
                id: $0.id,
                type: $0.eventType,
                kind: InsightDoseEventKind(eventType: $0.eventType),
                timestamp: $0.occurredAtUTC,
                details: $0.details
            )
        }

        let dose1Time = mappedEvents.first(where: { $0.kind == .dose1 })?.timestamp
            ?? session?.startedUTC
            ?? supplement?.dose1TimeUTC
        let dose2Time = mappedEvents.first(where: { $0.kind == .dose2 })?.timestamp
            ?? session?.endedUTC
            ?? supplement?.dose2TimeUTC
        let dose2Skipped = mappedEvents.contains(where: { $0.kind == .dose2Skipped }) || session?.adherenceFlag == "missed"
        let snoozeCount = mappedEvents.filter { $0.kind == .snooze }.count
        let startedAt = session?.startedUTC ?? mappedEvents.first?.timestamp
        let endedAt = session?.endedUTC ?? mappedEvents.last?.timestamp
        let sleepEfficiency = session?.sleepEfficiency ?? supplement?.whoop?.sleepEfficiency
        let whoopRecovery = session?.whoopRecovery ?? supplement?.whoop?.recoveryScore.map { Int($0.rounded()) }
        let averageHeartRate = session?.avgHR ?? supplement?.healthKit?.averageHeartRate

        guard session != nil || !mappedEvents.isEmpty else {
            return nil
        }

        return InsightSession(
            id: key,
            sessionDate: key,
            startedAt: startedAt,
            endedAt: endedAt,
            dose1Time: dose1Time,
            dose2Time: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            adherenceFlag: session?.adherenceFlag,
            sleepEfficiency: sleepEfficiency,
            whoopRecovery: whoopRecovery,
            averageHeartRate: averageHeartRate,
            notes: session?.notes,
            events: mappedEvents,
            preSleep: supplement?.preSleep,
            morning: supplement?.morning,
            medications: supplement?.medications ?? [],
            context: supplement?.context,
            healthKit: supplement?.healthKit,
            whoop: supplement?.whoop,
            rawEvents: supplement?.rawEvents ?? [],
            normalizedEvents: supplement?.normalizedEvents ?? [],
            sourceAvailability: supplement?.sourceAvailability,
            metricProvenance: supplement?.metricProvenance ?? [:],
            dataQualityFlags: supplement?.dataQualityFlags ?? [],
            exportExclusionReasons: supplement?.exportExclusionReasons ?? [],
            validationFlags: validationFlags
        )
    }

    private func sessionKey(for date: Date) -> String {
        Self.sessionDateFormatter.string(from: date)
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}
