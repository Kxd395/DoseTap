import Foundation
import DoseCore

struct PhysicianDaytimeCapture {
    let records: DaytimeTrendRecords
    let analysis: DaytimeDiaryAnalysis
    let asOf: Date
}

@MainActor
extension DashboardAnalyticsModel {
    func physicianDaytimeCapture(for period: PhysicianReportPeriod) throws -> PhysicianDaytimeCapture {
        try period.validate()
        let selection = try validatedSharedDaytimeSelection()
        guard selection.contextIssue == nil, selection.timeZone.identifier == period.timeZoneIdentifier,
              period.endExclusive <= selection.asOf else { throw PhysicianReviewError.invalidRevision }
        let records = try DaytimeTrendRecords(repository: sessionRepo, asOf: selection.asOf)
        let contexts = try Dictionary(uniqueKeysWithValues: records.observations.map {
            ($0.id, try DaytimeObservationContext(observation: $0, work: selection.work, basis: selection.basis,
                medication: selection.medication, asOf: selection.asOf, wake: records.wakeContexts[$0.id]))
        })
        let analysis = try DaytimeDiaryAnalysis(observations: records.observations, events: records.events,
            start: period.start, end: period.endExclusive, now: selection.asOf, timeZone: selection.timeZone,
            includesEnd: false, contexts: contexts)
        return .init(records: records, analysis: analysis, asOf: selection.asOf)
    }

    func physicianPromptHistory(for period: PhysicianReportPeriod) throws -> [PhysicianReportObservation] {
        let ledger = try sessionRepo.daytimePrompts()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        var result: [PhysicianReportObservation] = []
        for prompt in ledger.prompts {
            guard let schedule = ledger.schedules.first(where: { $0.id == prompt.scheduleID }) else { throw PhysicianReviewError.invalidRevision }
            // Do not capture an actual response or configuration written after the frozen source cutoff.
            guard schedule.createdAt <= reportingAsOf,
                  [prompt.openedAt, prompt.respondedAt, prompt.assessedAt].compactMap({ $0 }).allSatisfy({ $0 <= reportingAsOf })
            else { throw PhysicianReviewError.invalidRevision }
            let raw = String(decoding: try encoder.encode(prompt), as: UTF8.self)
            let rule = String(decoding: try encoder.encode(schedule), as: UTF8.self)
            let phases: [(String, Date?)] = [("intended", prompt.intendedAt), ("opened", prompt.openedAt),
                ("responded", prompt.respondedAt), ("assessed", prompt.assessedAt)]
            for (phase, time) in phases {
                guard let time, time <= reportingAsOf, period.contains(time) else { continue }
                result.append(.init(id: "prompt:" + prompt.id.uuidString + ":" + phase, observedAt: time,
                    metricID: "Daytime reminder " + phase, value: nil, state: .notApplicable, unit: "record",
                    source: "DoseTap reminder ledger", definitionVersion: "daytime-prompt-report.v1",
                    detail: "Intended time is planned, not observed delivery. Opening is not answering. No response is not proof of sleep.\nSource timestamps below use Unix seconds. Original anchor source/revision and schedule rule are retained.\n" + raw + "\nSchedule: " + rule,
                    recordIDs: [prompt.id.uuidString, prompt.scheduleID.uuidString], detailOnly: true))
            }
        }
        return result
    }

    func physicianMorningCoverage() throws -> [PhysicianReportContext] {
        // The shared projection keeps legacy defaults unconfirmed and unknown assessment times unplaced.
        var lines = ["Saved morning answers may include defaults or carried-forward values. Unknown assessment times are not reconstructed from treatment dates."]
        var ids: Set<String> = []
        for metric in ContextMorningMetric.allCases where !metric.duration {
            let report = contextOutcomeReport(metric: metric, grouping: .dayDemand)
            lines.append("\(metric.rawValue): \(report.eligibleCount) confirmed eligible observations; \(report.excludedCount) excluded/unconfirmed; \(report.unknownContextCount) have unknown following-day context.")
            ids.formUnion(report.observations.map(\.id))
        }
        lines.append("Grouping context is the explicitly reported following day. Raw saved details and serious flags remain in source detail; no derived clinical score or medication-effect conclusion is produced.")
        return [try .init(id: "morning-confirmation-coverage", title: "Morning answer confirmation and coverage", lines: lines,
            source: "Shared context and morning-outcome projection", definitionVersion: ContextOutcomeComparison.derivationVersion,
            recordIDs: ids.sorted())]
    }
}
