import Foundation
import DoseCore

@MainActor
extension SessionRepository {
    /// Read-only reporting. Does not allocate revisions, persist a cache, send a
    /// notification, query providers, upload data, or enter bidirectional sync.
    func dashboardSnapshot(sourceID: String, sequence: UInt64) throws -> CloudDashboardSnapshot {
        try storage.dashboardSnapshot(sourceID: sourceID, sequence: sequence, capturedAt: clock())
    }
}
