import Foundation
import DoseCore

@MainActor
enum DashboardAssociationUITestFixture {
    #if DEBUG && targetEnvironment(simulator)
    static func prepareNapDose(storage: EventStorage, at date: Date) -> Bool {
        storage.saveDose1(timestamp: date, sessionId: "synthetic-nap-dose-session",
            sessionDateOverride: storage.sessionDateString(for: date), sessionStart: date).isCommitted
    }
    #endif
    static func dependencies(arguments: [String] = ProcessInfo.processInfo.arguments) -> (repository: SessionRepository, queries: DashboardProviderQueries)? {
        #if DEBUG && targetEnvironment(simulator)
        if arguments.contains("-dashboard-dose-pattern-overlap-uitest") { return overlapDependencies() }
        let automatic = arguments.contains("-dashboard-auto-pair-uitest")
        guard automatic || arguments.contains("-dashboard-provider-match-uitest") else { return nil }
        let storage = EventStorage.inMemory(), repository = SessionRepository(storage: EventStorage.inMemory())
        let disabled = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let fallback = (repository, disabled)
        let now = Date(), calendar = Calendar.current
        guard let today = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
              let latestEvening = today > now ? calendar.date(byAdding: .day, value: -1, to: today) : Optional(today),
              let evening = automatic ? calendar.date(byAdding: .day, value: -1, to: latestEvening) : Optional(latestEvening) else { return fallback }
        let key = AppFormatters.sessionDate.string(from: evening)
        guard case .committed = storage.saveDose1(timestamp: evening.addingTimeInterval(3600),
            sessionId: "association-ui-session", sessionDateOverride: key) else { return fallback }
        if automatic {
            guard case .committed = storage.saveDose2(timestamp: evening.addingTimeInterval(4 * 3600),
                sessionId: "association-ui-session", sessionDateOverride: key) else { return fallback }
        }
        let summary = HealthKitService.SleepNightSummary(date: evening, bedTime: evening.addingTimeInterval(3600),
            sleepOnset: evening.addingTimeInterval(automatic ? 3900 : 4 * 3600), firstWake: nil, finalWake: evening.addingTimeInterval(8 * 3600),
            ttfwMinutes: nil, totalSleepMinutes: 415, wakeCount: 0, source: "Synthetic UI Test Watch")
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in [summary] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        return (SessionRepository(storage: storage), queries)
        #else
        return nil
        #endif
    }

    private static func overlapDependencies() -> (repository: SessionRepository, queries: DashboardProviderQueries)? {
        #if DEBUG && targetEnvironment(simulator)
        let storage = EventStorage.inMemory(), repository = SessionRepository(storage: storage)
        let disabled = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let fallback = (SessionRepository(storage: EventStorage.inMemory()), disabled)
        let now = Date(), calendar = Calendar.current
        guard let today = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) else { return fallback }
        var episodes: [(String, HealthKitService.SleepNightSummary)] = []
        for (index, suffix) in ["a", "b", "c"].enumerated() {
            guard let evening = calendar.date(byAdding: .day, value: index - 3, to: today) else { return fallback }
            let key = AppFormatters.sessionDate.string(from: evening), id = "overlap-" + suffix
            let first = evening.addingTimeInterval(3600)
            guard case .committed = storage.saveDose1(timestamp: first, sessionId: id, sessionDateOverride: key) else { return fallback }
            if suffix != "c" {
                guard case .committed = storage.saveDose2(timestamp: first.addingTimeInterval(180 * 60), sessionId: id, sessionDateOverride: key) else { return fallback }
            }
            let end = first.addingTimeInterval(420 * 60)
            episodes.append((id, .init(date: evening, bedTime: first, sleepOnset: first, firstWake: nil, finalWake: end,
                ttfwMinutes: nil, totalSleepMinutes: 420, wakeCount: 0, source: "Synthetic overlap test watch",
                recordedIntervals: [.init(start: first, end: end, asleep: true)])))
        }
        do {
            let snapshot = try repository.dashboardIdentitySnapshot()
            for (id, summary) in episodes {
                guard let session = snapshot.sessions.first(where: { $0.sessionID == id }), !session.needsReview else { return fallback }
                try repository.saveDashboardAssociation(.init(episodeID: summary.id, provider: "apple-health", sessionID: id,
                    sessionDate: session.sessionDate, sessionFingerprint: session.fingerprint,
                    episodeFingerprint: summary.associationFingerprint, revision: UUID().uuidString), expectedRevision: nil)
                if id == "overlap-c" {
                    guard let fingerprint = DashboardDoseReview.observationFingerprint(observationID: session.id,
                        sessionDate: session.sessionDate, events: session.doses) else { return fallback }
                    try repository.saveDashboardDoseReview(.init(observationID: session.id, sourceFingerprint: fingerprint,
                        confirmedCount: 1, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now,
                        reason: "Synthetic complete one-dose report"), sessionDate: session.sessionDate, expectedRevision: nil)
                }
            }
        } catch { return fallback }
        let summaries = episodes.map(\.1)
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in summaries },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        return (repository, queries)
        #else
        return nil
        #endif
    }
}
