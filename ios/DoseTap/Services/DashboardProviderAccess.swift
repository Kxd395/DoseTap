import Foundation
import Combine
import DoseCore

/// In-memory access epochs only. Never stores credentials or provider measurements.
final class DashboardProviderAccess {
    enum Provider: Hashable, Sendable { case health, whoop }
    typealias Revision = [Provider: UUID]
    static let shared = DashboardProviderAccess()
    let changes = PassthroughSubject<Provider, Never>()
    private let lock = NSLock()
    private var epochs: Revision = [.health: UUID(), .whoop: UUID()]

    var revision: Revision {
        lock.lock(); defer { lock.unlock() }
        return epochs
    }

    func invalidate(_ provider: Provider) {
        lock.lock(); epochs[provider] = UUID(); lock.unlock()
        // Subscribers may read the revision synchronously; never send under the lock.
        changes.send(provider)
    }
}

/// Dashboard-only query seam; tests never need a live provider or permission prompt.
@MainActor
struct DashboardProviderQueries {
    var healthEnabled: () -> Bool
    var whoopEnabled: () -> Bool
    var whoopConnected: () -> Bool
    var prepareHealth: () async -> Bool
    var healthHistory: (DashboardReportingWindow) async throws -> [HealthKitService.SleepNightSummary]
    var whoopHistory: (Date, Date) async throws -> [WHOOPNightSummary]

    static var live: Self {
        Self(healthEnabled: { UserSettingsManager.shared.healthKitEnabled },
             whoopEnabled: { WHOOPService.isEnabled && UserSettingsManager.shared.whoopEnabled },
             whoopConnected: { WHOOPService.shared.isConnected },
             prepareHealth: {
                 await HealthKitService.shared.syncAuthorizationState()
                 return HealthKitService.shared.isAuthorized
             }, healthHistory: { window in
                 var calendar = Calendar(identifier: .gregorian); calendar.timeZone = window.timeZone
                 return try await HealthKitService.shared.dashboardSleepHistory(
                    days: window.healthQueryDays, through: window.asOf, calendar: calendar)
             }, whoopHistory: { start, end in
                 try await WHOOPService.shared.fetchNightSummaries(from: start, to: end)
             })
    }
}
