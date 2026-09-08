import SwiftUI
import Charts
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

let dashboardLogger = Logger(subsystem: "com.dosetap.app", category: "Dashboard")

@MainActor
final class DashboardAnalyticsModel: ObservableObject {
    @Published var nights: [DashboardNightAggregate] = []
    @Published var integrationStates: [DashboardIntegrationState] = []
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var sleepSource: DashboardSleepSource = .appleHealth
    @Published var selectedRange: DashboardDateRange = .month

    let now: () -> Date

    init(now: @escaping () -> Date = Date.init, sessionRepo: SessionRepository? = nil) {
        self.now = now
        self.sessionRepo = sessionRepo ?? .shared
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

}

#if DEBUG && targetEnvironment(simulator)
import Foundation

extension DashboardAnalyticsModel {
    /// Deterministic display-only fixtures. Never writes to a repository or requests provider access.
    func loadDashboardUITestFixtureIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting-dashboard") else { return false }
        nights = []
        if !arguments.contains("--dashboard-empty") {
            nights = (1...8).map { offset in
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: now())!
                let key = Self.keyFormatter.string(from: date)
                let health = HealthKitService.SleepNightSummary(date: date, bedTime: nil, sleepOnset: nil,
                    firstWake: nil, finalWake: nil, ttfwMinutes: 180, totalSleepMinutes: Double(390 + offset * 10), wakeCount: 2, source: "UI test")
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
