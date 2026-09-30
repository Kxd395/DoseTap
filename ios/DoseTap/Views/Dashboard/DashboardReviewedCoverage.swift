import Foundation
import DoseCore

extension DashboardAnalyticsModel {
    /// Shared read-only coverage gate. The date-scoped loader cannot choose among multiple sessions on one date.
    func dashboardReviewedCoverage(sessionID: String) async -> ReviewedNightSleepResult {
        guard let night = populatedNights.first(where: { $0.sessionID == sessionID }),
              !night.identityNeedsReview,
              Set(nights.filter { $0.sessionDate == night.sessionDate }.compactMap(\.sessionID)).count == 1 else {
            return .init(status: .needsReview)
        }
        let access = providerAccess.revision
        let result = await sessionRepo.reviewedNightSleep(sessionDate: night.sessionDate)
        guard access == providerAccess.revision,
              populatedNights.contains(where: { $0.sessionID == sessionID && $0.sessionDate == night.sessionDate && !$0.identityNeedsReview }),
              Set(nights.filter { $0.sessionDate == night.sessionDate }.compactMap(\.sessionID)).count == 1 else {
            return .init(status: .stale)
        }
        guard result.window == nil || result.window?.sessionID == sessionID else { return .init(status: .needsReview) }
        return result
    }
}
