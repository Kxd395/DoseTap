import Foundation
import DoseCore

/// Explicit simulator-only display fixtures; no production fallback, storage mutation or provider request.
@MainActor
enum DashboardReplayUITestFixture {
    static var enabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--uitesting-replay")
        #else
        return false
        #endif
    }
    static func medications(model: DashboardAnalyticsModel) throws -> [ReplayMedication]? {
        guard enabled, let night = model.nights.first, let start = night.dose1Time else { return nil }
        return try [("XR", "extended_release", -7200.0), ("IR", "immediate_release", -3600.0)].map { label, release, delta in
            try ReplayMedication(.quick(.init(id: "synthetic-" + label, sessionId: nil, sessionDate: night.sessionDate,
                medicationId: "Synthetic " + label, doseMg: 5, takenAtUTC: start.addingTimeInterval(delta), doseUnit: "mg",
                formulation: release, localOffsetMinutes: 0, notes: nil, confirmedDuplicate: false, createdAt: start)))
        }
    }
    static func events(at date: Date, sessionDate: String) -> [StoredSleepEvent] {
        guard enabled else { return [] }
        return [("nap_start", -10_800.0), ("nap_end", -9000.0), ("pain", -1800.0)].map { kind, delta in
            .init(id: "synthetic-" + kind + sessionDate, eventType: kind, timestamp: date.addingTimeInterval(delta), sessionDate: sessionDate)
        }
    }
    static func doseMetadata(for night: DashboardNightAggregate) -> String? {
        guard enabled, let sessionID = night.sessionID, let dose = night.dose1Time else { return nil }
        let warning: [String: Any] = ["sessionId": sessionID, "revision": "00000000-0000-0000-0000-000000000123",
            "wakeDate": night.sessionDate, "timeZoneIdentifier": "UTC", "requiredWake": dose.addingTimeInterval(8 * 3600).timeIntervalSinceReferenceDate,
            "targetAt": dose.timeIntervalSinceReferenceDate, "target": WorkWarningTarget.doseTarget.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: ["reminder_interval_minutes": 165, "work_warning_acknowledgement": warning]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func coverage(model: DashboardAnalyticsModel, sessionID: String) -> ReviewedNightSleepResult? {
        guard enabled, let night = model.nights.first(where: { $0.sessionID == sessionID }),
              let start = night.dose1Time, let summary = night.healthSummary, let end = summary.finalWake else { return nil }
        let now = model.reportingAsOf
        let window = ReviewedSleepWindow(sessionID: sessionID, start: start, end: end,
            entryTimeZone: model.reportingTimeZone, reviewedAt: now)
        let samples: [SleepEvidenceSample] = summary.recordedIntervals.enumerated().map { index, interval in
            .init(sampleID: "synthetic-interval-\(index)", start: interval.start, end: interval.end, rawCategory: 0,
                stage: interval.asleep ? .asleep : .awake, origin: .init(sourceName: "Synthetic reviewed UI fixture", bundleIdentifier: nil))
        }
        guard let evidence = SleepEvidenceResolution.calculate(start: start, end: end, samples: samples),
              let projection = ReviewedNightSleepProjection.calculate(window: window, evidence: evidence, generatedAt: now) else { return nil }
        return .init(status: .partial, window: window, evidence: evidence, checkedAt: now, projection: projection,
            doseSleepMetrics: .calculate(projection: projection, doses: night.doseEvents))
    }
}
