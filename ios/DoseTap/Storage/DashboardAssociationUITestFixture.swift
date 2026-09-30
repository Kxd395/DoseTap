import Foundation

@MainActor
enum DashboardAssociationUITestFixture {
    static func dependencies() -> (repository: SessionRepository, queries: DashboardProviderQueries)? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("-dashboard-provider-match-uitest") else { return nil }
        let storage = EventStorage.inMemory(), repository = SessionRepository(storage: EventStorage.inMemory())
        let disabled = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let fallback = (repository, disabled)
        let now = Date(), calendar = Calendar.current
        guard let today = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
              let evening = today > now ? calendar.date(byAdding: .day, value: -1, to: today) : Optional(today) else { return fallback }
        let key = AppFormatters.sessionDate.string(from: evening)
        guard case .committed = storage.saveDose1(timestamp: evening.addingTimeInterval(3600),
            sessionId: "association-ui-session", sessionDateOverride: key) else { return fallback }
        let summary = HealthKitService.SleepNightSummary(date: evening, bedTime: evening.addingTimeInterval(3600),
            sleepOnset: evening.addingTimeInterval(3900), firstWake: nil, finalWake: evening.addingTimeInterval(8 * 3600),
            ttfwMinutes: nil, totalSleepMinutes: 415, wakeCount: 0, source: "Synthetic UI Test Watch")
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in [summary] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        return (SessionRepository(storage: storage), queries)
        #else
        return nil
        #endif
    }
}
