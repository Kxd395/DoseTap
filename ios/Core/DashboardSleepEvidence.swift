import Foundation

/// One bounded, successful provider query. Empty means no readable samples.
/// This does not assert read authorization, complete sleep coverage or a night total.
public struct DashboardSleepEvidence: Codable, Equatable, Sendable {
    public static let maximumSamples = 10_000
    public static let maximumRange: TimeInterval = 30 * 86_400
    public var version = 1
    public var queryStart: Date
    public var queryEnd: Date
    public var completedAt: Date
    public var timeZoneID: String
    public var samples: [SleepEvidenceSample]

    public init(queryStart: Date, queryEnd: Date, completedAt: Date,
                timeZoneID: String, samples: [SleepEvidenceSample]) {
        self.queryStart = queryStart; self.queryEnd = queryEnd
        self.completedAt = completedAt; self.timeZoneID = timeZoneID; self.samples = samples
    }

    public func validate(capturedAt: Date) throws {
        guard version == 1,
              [queryStart, queryEnd, completedAt, capturedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              queryStart < queryEnd, queryEnd.timeIntervalSince(queryStart) <= Self.maximumRange,
              queryEnd <= completedAt, completedAt <= capturedAt,
              TimeZone(identifier: timeZoneID) != nil, samples.count <= Self.maximumSamples else {
            throw DashboardSnapshotError.invalidPayload
        }
        var ids = Set<String>()
        for sample in samples {
            guard let id = sample.sampleID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(id).inserted,
                  sample.start.timeIntervalSince1970.isFinite, sample.end.timeIntervalSince1970.isFinite,
                  sample.start < sample.end, sample.start < queryEnd, sample.end > queryStart,
                  sample.end <= completedAt,
                  !sample.origin.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DashboardSnapshotError.invalidPayload
            }
            if let received = sample.origin.receivedAt {
                guard received.timeIntervalSince1970.isFinite, received <= completedAt else {
                    throw DashboardSnapshotError.invalidPayload
                }
            }
            let stage: SleepEvidenceSample.Stage
            switch sample.rawCategory {
            case 0: stage = .inBed
            case 1: stage = .asleep
            case 2: stage = .awake
            case 3: stage = .core
            case 4: stage = .deep
            case 5: stage = .rem
            default: stage = .unknown
            }
            guard stage == sample.stage else { throw DashboardSnapshotError.invalidPayload }
        }
    }

    public func section() throws -> DashboardSnapshotSection {
        try validate(capturedAt: completedAt)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return .init(dataset: .appleHealth, rows: try encoder.encode([self]), rowCount: 1)
    }

    /// Envelope integrity is checked by CloudDashboardCache before display. This
    /// additional typed validation prevents malformed provider bytes entering cache.
    public static func read(from snapshot: CloudDashboardSnapshot) throws -> Self? {
        guard let section = snapshot.sections.first(where: { $0.dataset == .appleHealth }),
              section.unavailableReason == nil, let rows = section.rows else { return nil }
        let packets = try JSONDecoder().decode([Self].self, from: rows)
        if packets.isEmpty { return nil } // Legacy empty section is not a query result.
        guard packets.count == 1 else { throw DashboardSnapshotError.invalidPayload }
        try packets[0].validate(capturedAt: snapshot.capturedAt)
        return packets[0]
    }
}
