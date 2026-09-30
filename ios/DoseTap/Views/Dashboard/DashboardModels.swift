import SwiftUI
import Charts
import DoseCore
import os.log
import Combine
#if canImport(UIKit)
import UIKit
#endif

let dashboardLogger = Logger(subsystem: "com.dosetap.app", category: "Dashboard")

@MainActor
final class DashboardAnalyticsModel: ObservableObject {
    @Published var nights: [DashboardNightAggregate] = []
    @Published var inspection = DashboardInspectionState()
    @Published var integrationStates: [DashboardIntegrationState] = []
    @Published var isLoading = false
    @Published var savedProviderAssociations: [DashboardProviderAssociation] = []
    var providerAssociationsReady = false
    @Published var doseReviewReadReady = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var sleepSource: DashboardSleepSource = .appleHealth
    @Published var selectedRange: DashboardDateRange = .month

    @Published var reportingAsOf: Date
    @Published var reportingTimeZone: TimeZone
    @Published var healthQueryWindow: DashboardReportingWindow?
    @Published var healthSnapshot: DashboardProviderSnapshot<HealthKitService.SleepNightSummary>?
    @Published var whoopSnapshot: DashboardProviderSnapshot<WHOOPNightSummary>?
    let timeZone: () -> TimeZone
    let now: () -> Date
    let providerAccess: DashboardProviderAccess
    let providerQueries: DashboardProviderQueries
    var publishedProviderAccess: DashboardProviderAccess.Revision
    var refreshProviderAccess: DashboardProviderAccess.Revision?
    private var providerAccessSubscription: AnyCancellable?

    init(now: @escaping () -> Date = Date.init, sessionRepo: SessionRepository? = nil,
         timeZone: @escaping () -> TimeZone = { .current },
         providerAccess: DashboardProviderAccess = .shared, providerQueries: DashboardProviderQueries? = nil) {
        self.now = now
        self.timeZone = timeZone
        reportingAsOf = now()
        reportingTimeZone = timeZone()
        let fixture = sessionRepo == nil && providerQueries == nil ? DashboardAssociationUITestFixture.dependencies() : nil
        self.sessionRepo = sessionRepo ?? fixture?.repository ?? .shared
        self.providerAccess = providerAccess
        self.providerQueries = providerQueries ?? fixture?.queries ?? .live
        publishedProviderAccess = providerAccess.revision
        providerAccessSubscription = providerAccess.changes.sink { [weak self] provider in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.providerAccessChanged(provider) }
            } else {
                Task { @MainActor [weak self] in self?.providerAccessChanged(provider) }
            }
        }
    }

    let sessionRepo: SessionRepository
    let settings = UserSettingsManager.shared
    let healthKit = HealthKitService.shared
    let whoop = WHOOPService.shared
    let cloudSync = DeferredCloudKitSyncService.shared

    /// Cancels in-flight refresh when a new one starts (prevents race on rapid range changes).
    var refreshGeneration = UUID()
    var refreshTask: Task<Void, Never>?

    static let keyFormatter: DateFormatter = AppFormatters.sessionDate

    func providerSnapshotIsCurrent(_ provider: DashboardProviderAccess.Provider) -> Bool {
        guard !isLoading, providerAssociationsReady else { return false }
        func current<T>(_ snapshot: DashboardProviderSnapshot<T>?) -> Bool {
            guard let snapshot else { return false }
            return snapshot.failedAttemptAt == nil && snapshot.window.range == selectedRange
                && snapshot.window.asOf == reportingAsOf && reportingTimeZone == timeZone()
                && snapshot.matches(timeZone: reportingTimeZone, epoch: providerAccess.revision[provider])
        }
        if provider == .health { return providerQueries.healthEnabled() && current(healthSnapshot) }
        return providerQueries.whoopEnabled() && providerQueries.whoopConnected() && current(whoopSnapshot)
    }

    func providerAccessChanged(_ provider: DashboardProviderAccess.Provider) {
        let current = providerAccess.revision
        // A delayed notification must not erase a newer, already validated publication.
        guard publishedProviderAccess[provider] != current[provider] else { return }
        if refreshProviderAccess != current {
            refreshTask?.cancel(); refreshGeneration = UUID(); isLoading = false
        }
        nights = nights.map { night in
            var row = night
            if provider == .health { row.healthSummary = nil } else { row.whoopSummary = nil }
            return row
        }.filter { $0.hasAnyData || $0.napSummary.count > 0 || $0.snoozeCount > 0 }
        if provider == .health { healthQueryWindow = nil; healthSnapshot = nil } else { whoopSnapshot = nil }
        publishedProviderAccess[provider] = current[provider]
        integrationStates = buildIntegrationStates(healthMatches: nights.filter { $0.healthSummary != nil }.count,
            whoopMatches: nights.filter { $0.whoopSummary != nil }.count)
        errorMessage = "Provider access changed. Refresh the dashboard to check current availability."
        dashboardLogger.info("Dashboard provider access changed; previous provider results invalidated")
    }
}

#if DEBUG && targetEnvironment(simulator)
import Foundation

extension DashboardAnalyticsModel {
    /// Deterministic display-only fixtures. Never writes to a repository or requests provider access.
    func loadDashboardUITestFixtureIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting-dashboard") else { return false }
        reportingAsOf = now(); reportingTimeZone = timeZone()
        healthQueryWindow = currentReportWindow
        nights = []
        if !arguments.contains("--dashboard-empty") {
            nights = (1...8).map { offset in
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: now())!
                let key = Self.keyFormatter.string(from: date)
                var health = HealthKitService.SleepNightSummary(date: date, bedTime: nil, sleepOnset: date.addingTimeInterval(600),
                    firstWake: nil, finalWake: date.addingTimeInterval(Double(390 + offset * 10) * 60 + 1200), ttfwMinutes: 180, totalSleepMinutes: Double(390 + offset * 10), wakeCount: 2, source: "UI test")
                health.recordedIntervals = [.init(start: date.addingTimeInterval(600), end: date.addingTimeInterval(12_000), asleep: true),
                    .init(start: date.addingTimeInterval(12_000), end: date.addingTimeInterval(12_600), asleep: false),
                    .init(start: date.addingTimeInterval(12_600), end: date.addingTimeInterval(Double(390 + offset * 10) * 60 + 1200), asleep: true)]
                let whoop = WHOOPNightSummary(date: date, sleepId: key, totalSleepMinutes: 450,
                    remMinutes: 90, deepMinutes: 75, lightMinutes: 285, awakeMinutes: 30,
                    inBedMinutes: 480, disturbanceCount: 3, sleepEfficiency: 93.75,
                    sleepPerformance: nil, sleepConsistency: nil, respiratoryRate: 16,
                    sleepNeedBaselineMinutes: nil, sleepNeedDebtMinutes: nil, sleepNeedStrainMinutes: nil, sleepNeedNapMinutes: nil,
                    recoveryScore: 65, hrvMs: 42)
                var preSleep = PreSleepLogAnswers(stressLevel: offset % 5 + 1, stimulants: .coffee, screensInBed: PreSleepLogAnswers.ScreensInBed.none)
                if offset % 3 != 0 {
                    preSleep.lastFood = .init(finishedAt: date.addingTimeInterval(-Double(100 + offset * 20) * 60),
                        kind: .meal, highFat: offset == 7 ? nil : offset % 2 == 0)
                }
                var aggregate = DashboardNightAggregate(sessionDate: key, dose1Time: date,
                    dose2Time: offset == 2 ? nil : date.addingTimeInterval(Double(140 + offset * 15) * 60),
                    dose2Skipped: offset == 2, snoozeCount: 1, extraDoseCount: 0, events: [],
                    morningCheckIn: .init(id: key, sessionId: key, timestamp: date, sessionDate: key, sleepQuality: 3, stressLevel: offset % 5 + 1),
                    preSleepLog: .init(id: key, sessionId: key, createdAtUtc: "", localOffsetMinutes: 0, completionState: "complete",
                        answers: preSleep),
                    healthSummary: health, whoopSummary: offset > 3 ? whoop : nil,
                    duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
                var diary = NightOutcomeDiary()
                diary.wakeMethod = offset > 6 ? .unknown : (offset % 2 == 0 ? .alarm : .natural)
                diary.dayType = offset % 2 == 0 ? .workday : .dayOff
                if offset % 3 == 0 || offset == 4 || offset == 5 {
                    diary.sleepiness = offset == 4 ? 0 : offset
                    diary.assessedAt = date.addingTimeInterval(14 * 3600)
                }
                aggregate.sessionID = key; aggregate.stableID = "session:" + key; aggregate.sessionClosed = true
                aggregate.providerAssociation = "Synthetic resolved association"
                aggregate.doseEvents = [.init(id: "d1:" + key, eventType: "dose1", timestamp: date, sessionDate: key, sessionId: key)]
                if let second = aggregate.dose2Time {
                    aggregate.doseEvents.append(.init(id: "d2:" + key, eventType: "dose2", timestamp: second, sessionDate: key, sessionId: key))
                }
                aggregate.outcome = diary
                return aggregate
            }
        }
        if arguments.contains("--dashboard-sparse") { nights = Array(nights.prefix(2)) }
        integrationStates = []
        errorMessage = arguments.contains("--dashboard-partial") ? "WHOOP sleep could not refresh. Local records are still available. Try Refresh again." : nil
        lastRefresh = now()
        isLoading = false
        return true
    }
}
#endif
