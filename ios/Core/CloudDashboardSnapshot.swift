import Foundation
import CryptoKit

/// Reporting-only datasets. No source mutation or alarm capability is exposed.
public enum DashboardDataset: String, Codable, CaseIterable, Sendable {
    case sessions, doseEvents, quickLogs, preSleep, morning, normalizedAnswers
    case medicationEntries, presetVersions, administrations, amendments
    case daytimeDiary, reviewedSleepWindows, inventory, appleHealth, whoop

    public var isProvider: Bool { self == .appleHealth || self == .whoop }
}

public struct DashboardSnapshotSection: Codable, Equatable, Sendable {
    public var dataset: DashboardDataset
    public var rows: Data?
    public var rowCount: Int?
    public var sha256: String?
    public var unavailableReason: String?

    public init(dataset: DashboardDataset, rows: Data, rowCount: Int) {
        self.dataset = dataset
        self.rows = rows
        self.rowCount = rowCount
        self.sha256 = Self.digest(rows)
        self.unavailableReason = nil
    }

    public init(unavailable dataset: DashboardDataset, reason: String) {
        self.dataset = dataset
        self.rows = nil
        self.rowCount = nil
        self.sha256 = nil
        self.unavailableReason = reason
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func validate() throws {
        if let reason = unavailableReason {
            guard dataset.isProvider, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  rows == nil, rowCount == nil, sha256 == nil else {
                throw DashboardSnapshotError.incompleteDataset
            }
            return
        }
        guard let rows, let rowCount, rowCount >= 0, sha256 == Self.digest(rows),
              let array = try? JSONSerialization.jsonObject(with: rows) as? [[String: Any]],
              array.count == rowCount else {
            throw DashboardSnapshotError.invalidPayload
        }
    }
}

public struct CloudDashboardSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceID: String
    public var sequence: UInt64
    public var capturedAt: Date
    public var sections: [DashboardSnapshotSection]

    public init(sourceID: String, sequence: UInt64, capturedAt: Date,
                sections: [DashboardSnapshotSection]) {
        self.sourceID = sourceID
        self.sequence = sequence
        self.capturedAt = capturedAt
        self.sections = sections
    }

    fileprivate func validate(now: Date) throws {
        guard schemaVersion == 1 else { throw DashboardSnapshotError.unsupportedSchema }
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sequence > 0,
              now.timeIntervalSince1970.isFinite, capturedAt.timeIntervalSince1970.isFinite,
              capturedAt <= now else { throw DashboardSnapshotError.invalidMetadata }
        guard sections.count == DashboardDataset.allCases.count,
              Set(sections.map(\.dataset)) == Set(DashboardDataset.allCases) else {
            throw DashboardSnapshotError.incompleteDataset
        }
        for section in sections { try section.validate() }
    }
}

public enum DashboardSnapshotError: Error, Equatable {
    case wrongContext, unsupportedSchema, invalidMetadata, incompleteDataset
    case invalidPayload, staleRevision, conflictingRevision
}

/// Pure in-memory acceptance state. The adapter owns authentication, request fencing,
/// byte limits and durable cache replacement; this type never writes clinical storage.
public struct CloudDashboardCache: Sendable {
    public private(set) var snapshot: CloudDashboardSnapshot?
    private var accountScope: String?
    private var sourceID: String?

    public init(accountScope: String?, sourceID: String?) {
        self.accountScope = accountScope
        self.sourceID = sourceID
    }

    public mutating func select(accountScope: String?, sourceID: String?) {
        if self.accountScope != accountScope || self.sourceID != sourceID {
            snapshot = nil
        }
        self.accountScope = accountScope
        self.sourceID = sourceID
    }

    /// Account scope must come from the authenticated request, never the payload.
    /// Returns false for an identical retry. Rejections leave the previous value intact.
    @discardableResult
    public mutating func accept(_ candidate: CloudDashboardSnapshot,
                                accountScope: String, now: Date) throws -> Bool {
        guard !accountScope.isEmpty, self.accountScope == accountScope,
              sourceID == candidate.sourceID else { throw DashboardSnapshotError.wrongContext }
        try candidate.validate(now: now)
        if let previous = snapshot {
            guard candidate.sequence >= previous.sequence else {
                throw DashboardSnapshotError.staleRevision
            }
            if candidate.sequence == previous.sequence {
                guard candidate == previous else { throw DashboardSnapshotError.conflictingRevision }
                return false
            }
        }
        snapshot = candidate
        return true
    }
}
