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
    @Published var nights: [DashboardNightAggregate] = [] { didSet { invalidateDisplayProjections() } }
    @Published var inspection = DashboardInspectionState() { didSet { invalidateDisplayProjections() } }
    @Published var replayPresentation = DashboardReplayPresentation() { didSet { invalidateDisplayProjections() } }
    var cachedReportingWindow: DashboardReportingWindow?
    var cachedPeriodRows: (current: [DashboardNightAggregate], prior: [DashboardNightAggregate])?
    var cachedReplaySnapshots: [DashboardReplaySnapshot]?
    var cachedReplayAccess: DashboardProviderAccess.Revision?
    var invalidReplayEndpointIDs: Set<String> = []
    func invalidateDisplayProjections() {
        cachedReportingWindow = nil; cachedPeriodRows = nil
        cachedReplaySnapshots = nil; cachedReplayAccess = nil
        invalidReplayEndpointIDs = []
    }
    let replayCoverageState = TimelineDoseSleepModel()
    var replaySourceSubscriptions: Set<AnyCancellable> = []
    @Published var contextPresentation = ContextMorningPresentation() { didSet { invalidateDisplayProjections() } }
    @Published var daytimeInspection = DaytimeInspectionState() { didSet { invalidateDisplayProjections() } }
    @Published var napInspection = DashboardNapInspection() { didSet { invalidateDisplayProjections() } }
    @Published var additionalMeasure = DashboardAdditionalMeasure.summary { didSet { invalidateDisplayProjections() } }
    @Published var workInspectionContext: WorkContextDocument? { didSet { invalidateDisplayProjections() } }
    @Published var workContextReadReady = false { didSet { invalidateDisplayProjections() } }
    @Published var workContextIssue: String? { didSet { invalidateDisplayProjections() } }
    var workInspectionAsOf: Date?
    var plannedWorkClassifications: [String: WorkPhaseResult] = [:]
    var confirmedWorkClassifications: [String: WorkPhaseResult] = [:]
    @Published var integrationStates: [DashboardIntegrationState] = [] { didSet { invalidateDisplayProjections() } }
    @Published var isLoading = false { didSet { invalidateDisplayProjections() } }
    @Published var savedProviderAssociations: [DashboardProviderAssociation] = [] { didSet { invalidateDisplayProjections() } }
    var providerAssociationsReady = false
    @Published var doseReviewReadReady = false { didSet { invalidateDisplayProjections() } }
    @Published var contextTimeline: DashboardContextTimeline? { didSet { invalidateDisplayProjections() } }
    @Published var contextReadReady = false { didSet { invalidateDisplayProjections() } }
    var contextAnnotations: [DashboardContextAnnotation] { contextReadReady ? contextTimeline?.annotations ?? [] : [] }
    @Published var lastRefresh: Date? { didSet { invalidateDisplayProjections() } }
    @Published var errorMessage: String? { didSet { invalidateDisplayProjections() } }
    @Published var sleepSource: DashboardSleepSource = .appleHealth { didSet { invalidateDisplayProjections() } }
    @Published var selectedRange: DashboardDateRange = .month { didSet { invalidateDisplayProjections() } }
    @Published var customReportingRange: PhysicianReportRange? { didSet { invalidateDisplayProjections() } }
    @Published var reportingPeriod: PhysicianReportPeriod? { didSet { invalidateDisplayProjections() } }
    var publishedCustomReportingRange: PhysicianReportRange?

    @Published var reportingAsOf: Date { didSet { invalidateDisplayProjections() } }
    @Published var reportingTimeZone: TimeZone { didSet { invalidateDisplayProjections() } }
    @Published var healthQueryWindow: DashboardReportingWindow? { didSet { invalidateDisplayProjections() } }
    @Published var healthSnapshot: DashboardProviderSnapshot<HealthKitService.SleepNightSummary>? { didSet { invalidateDisplayProjections() } }
    @Published var whoopSnapshot: DashboardProviderSnapshot<WHOOPNightSummary>? { didSet { invalidateDisplayProjections() } }
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
        let useReplayFixture = DashboardReplayUITestFixture.enabled && sessionRepo == nil && providerQueries == nil
        var dashboardNow = now
        if useReplayFixture {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone()
            let instant = now()
            let captured = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: instant) ?? calendar.startOfDay(for: instant)
            dashboardNow = { captured }
        }
        self.now = dashboardNow
        self.timeZone = timeZone
        reportingAsOf = dashboardNow()
        reportingTimeZone = timeZone()
        let fixture = sessionRepo == nil && providerQueries == nil ? DashboardAssociationUITestFixture.dependencies() : nil
        #if DEBUG && targetEnvironment(simulator)
        #if DEBUG && targetEnvironment(simulator)
        let replayRepository = useReplayFixture ? SessionRepository(storage: .inMemory(), clock: dashboardNow, timeZoneProvider: timeZone) : nil
        #else
        let replayRepository: SessionRepository? = nil
        #endif
        #else
        let replayRepository: SessionRepository? = nil
        #endif
        self.sessionRepo = sessionRepo ?? fixture?.repository ?? replayRepository ?? .shared
        self.providerAccess = providerAccess
        self.providerQueries = providerQueries ?? fixture?.queries ?? Self.dashboardDisplayFixtureQueries() ?? .live
        publishedProviderAccess = providerAccess.revision
        installReplaySourceObservation()
        replayCoverageState.objectWillChange.sink { [weak self] _ in
            self?.cachedReplaySnapshots = nil
        }.store(in: &replaySourceSubscriptions)
        providerAccessSubscription = providerAccess.changes.sink { [weak self] provider in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.providerAccessChanged(provider) }
            } else {
                Task { @MainActor [weak self] in self?.providerAccessChanged(provider) }
            }
        }
    }

    private static func dashboardDisplayFixtureQueries() -> DashboardProviderQueries? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("--uitesting-dashboard") else { return nil }
        return .init(healthEnabled: { true }, whoopEnabled: { true }, whoopConnected: { true },
            prepareHealth: { .ready }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        #else
        return nil
        #endif
    }

    let sessionRepo: SessionRepository
    let settings = UserSettingsManager.shared
    let healthKit = HealthKitService.shared
    let whoop = WHOOPService.shared
    let cloudSync = DeferredCloudKitSyncService.shared

    /// Cancels in-flight refresh when a new one starts (prevents race on rapid range changes).
    var localSnapshotRevision: UInt = 0
    var refreshGeneration = UUID()
    var refreshTask: Task<Void, Never>?

    static let keyFormatter: DateFormatter = AppFormatters.sessionDate

    func providerSnapshotIsCurrent(_ provider: DashboardProviderAccess.Provider) -> Bool {
        guard !isLoading, providerAssociationsReady else { return false }
        func current<T>(_ snapshot: DashboardProviderSnapshot<T>?) -> Bool {
            guard let snapshot else { return false }
            return snapshot.failedAttemptAt == nil && snapshot.window == currentReportWindow
                && snapshot.window.asOf == reportingAsOf && reportingTimeZone == timeZone()
                && publishedCustomReportingRange == customReportingRange
                && snapshot.matches(timeZone: reportingTimeZone, epoch: providerAccess.revision[provider])
        }
        if provider == .health { return providerQueries.healthEnabled() && current(healthSnapshot) }
        return providerQueries.whoopEnabled() && providerQueries.whoopConnected() && current(whoopSnapshot)
    }

    func invalidateContextPublication() {
        contextReadReady = false; contextTimeline = nil
        nights = nights.map { night in
            var row = night; row.contextProjection = nil; row.contextAnnotations = []
            return row
        }
    }

    func providerAccessChanged(_ provider: DashboardProviderAccess.Provider) {
        let current = providerAccess.revision
        // A delayed notification must not erase a newer, already validated publication.
        guard publishedProviderAccess[provider] != current[provider] else { return }
        if refreshProviderAccess != current {
            refreshTask?.cancel(); refreshGeneration = UUID(); isLoading = false
        }
        invalidateContextPublication()
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
    func loadDashboardUITestFixtureIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard arguments.contains("--uitesting-dashboard") else { return false }
        reportingAsOf = now(); reportingTimeZone = timeZone()
        invalidateContextPublication(); invalidateWorkInspectionContext()
        doseReviewReadReady = false; providerAssociationsReady = false
        guard let window = try? resolveReportingWindow(asOf: reportingAsOf, timeZone: reportingTimeZone) else {
            errorMessage = "The fixture reporting period is invalid."; return true
        }
        reportingPeriod = window.reviewedPeriod; publishedCustomReportingRange = customReportingRange
        healthQueryWindow = window
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = reportingTimeZone
        nights = []
        if !arguments.contains("--dashboard-empty") {
            nights = (1...8).map { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: reportingAsOf)!
                let key = sessionKey(for: date, timeZone: reportingTimeZone)
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
                    stageEvidence: .init(sleepID: key, scoreState: "SCORED", lightMilliseconds: 285 * 60_000,
                        deepMilliseconds: 75 * 60_000, remMilliseconds: 90 * 60_000),
                    recoveryScore: 65, hrvMs: 42)
                var preSleep = PreSleepLogAnswers(stressLevel: offset % 5 + 1, stimulants: .coffee, screensInBed: PreSleepLogAnswers.ScreensInBed.none)
                if offset % 3 != 0 {
                    preSleep.lastFood = .init(finishedAt: date.addingTimeInterval(-Double(100 + offset * 20) * 60),
                        kind: .meal, highFat: offset == 7 ? nil : offset % 2 == 0)
                }
                var aggregate = DashboardNightAggregate(sessionDate: key, dose1Time: date,
                    dose2Time: offset == 2 ? nil : date.addingTimeInterval(Double(140 + offset * 15) * 60),
                    dose2Skipped: offset == 2, snoozeCount: 1, extraDoseCount: 0, events: DashboardReplayUITestFixture.events(at: date, sessionDate: key),
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
                if let metadata = DashboardReplayUITestFixture.doseMetadata(for: aggregate) {
                    aggregate.doseEvents = aggregate.doseEvents.map { event in
                        .init(id: event.id, eventType: event.eventType, timestamp: event.timestamp, sessionDate: event.sessionDate,
                            metadata: event.eventType == "dose1" ? metadata : event.metadata, sessionId: event.sessionId)
                    }
                }
                return aggregate
            }
        }
        if arguments.contains("--dashboard-sparse") { nights = Array(nights.prefix(2)) }
        do {
            let snapshot = try sessionRepo.dashboardContextSnapshot(capturedAt: reportingAsOf)
            let reviews = try sessionRepo.dashboardDoseReviews()
            let work = arguments.contains("--uitesting-work-events") ? workEventDisplayFixture() : try sessionRepo.workContext()
            nights = nights.map { row in
                var row = row; row.applyContext(snapshot.timeline); row.doseReviewLedger = reviews[row.id]; return row
            }
            contextTimeline = snapshot.timeline; contextReadReady = true
            savedProviderAssociations = snapshot.associations; providerAssociationsReady = true; doseReviewReadReady = true
            publishWorkInspectionContext(work, nights: nights, asOf: reportingAsOf)
        } catch {
            errorMessage = "Fixture local records could not be read completely."; isLoading = false; return true
        }
        publishedProviderAccess = providerAccess.revision
        healthSnapshot = .init(values: Dictionary(uniqueKeysWithValues: nights.compactMap { row in row.healthSummary.map { (row.id, $0) } }),
            window: window, queryStart: window.healthQueryStart, epoch: publishedProviderAccess[.health])
        whoopSnapshot = .init(values: Dictionary(uniqueKeysWithValues: nights.compactMap { row in row.whoopSummary.map { (row.id, $0) } }),
            window: window, queryStart: window.healthQueryStart, epoch: publishedProviderAccess[.whoop])
        if arguments.contains("--dashboard-partial") { whoopSnapshot?.failedAttemptAt = reportingAsOf }
        integrationStates = []
        errorMessage = arguments.contains("--dashboard-partial") ? "WHOOP sleep could not refresh. Local records are still available. Try Refresh again." : nil
        lastRefresh = reportingAsOf
        isLoading = false
        return true
    }
}
#endif
