import Foundation

/// Sanitized derivation of one opted-in Apple Health episode, never an app-session clock.
public struct DashboardSharedSleepEpisode: Codable, Equatable, Sendable {
    public var version = 1
    public var episodeID: String
    public var treatmentDate: String
    public var source: String
    public var sessionID: String?
    public var associationRevision: UUID?
    public var intervals: [RecordedSleepInterval]
    public var bedTime: Date?
    public var sleepOnset: Date?
    public var finalWake: Date?
    public var observationEnd: Date?
    public var finalWakeBasis: String?
    public var derivationVersion: String?
    public var totalSleepMinutes: Double
    public var queryStart: Date
    public var queryEnd: Date
    public var completedAt: Date
    public var timeZoneID: String
    public var review: DashboardSharedProviderDoseReview? = nil

    public init(episodeID: String, treatmentDate: String, source: String, sessionID: String?,
                associationRevision: UUID?, intervals: [RecordedSleepInterval], bedTime: Date?,
                sleepOnset: Date?, finalWake: Date?, observationEnd: Date?, finalWakeBasis: String?,
                derivationVersion: String?, totalSleepMinutes: Double, queryStart: Date, queryEnd: Date,
                completedAt: Date, timeZoneID: String) {
        self.episodeID = episodeID; self.treatmentDate = treatmentDate; self.source = source
        self.sessionID = sessionID; self.associationRevision = associationRevision; self.intervals = intervals
        self.bedTime = bedTime; self.sleepOnset = sleepOnset; self.finalWake = finalWake
        self.observationEnd = observationEnd; self.finalWakeBasis = finalWakeBasis
        self.derivationVersion = derivationVersion; self.totalSleepMinutes = totalSleepMinutes
        self.queryStart = queryStart; self.queryEnd = queryEnd; self.completedAt = completedAt; self.timeZoneID = timeZoneID
    }

    public var coverage: SleepIntervalCoverage? {
        guard let start = ([bedTime, sleepOnset].compactMap { $0 } + intervals.map(\.start)).min(),
              let end = observationEnd else { return nil }
        return .calculate(start: start, end: end, intervals: intervals)
    }

    public func validate(capturedAt: Date) throws {
        func validText(_ text: String) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 4096 && !text.contains("\0")
        }
        guard version == 1, episodeID.hasPrefix("apple-health:"), validText(episodeID), validText(source),
              DashboardReportingWindow.isValidDateKey(treatmentDate), TimeZone(identifier: timeZoneID) != nil,
              (sessionID == nil) == (associationRevision == nil),
              sessionID.map({ validText($0) && $0 != treatmentDate }) ?? true,
              [queryStart, queryEnd, completedAt, capturedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              queryStart < queryEnd, queryEnd.timeIntervalSince(queryStart) <= DashboardSleepEvidence.maximumRange,
              queryEnd <= completedAt, completedAt <= capturedAt,
              totalSleepMinutes.isFinite, totalSleepMinutes >= 0,
              !intervals.isEmpty, intervals.count <= DashboardSleepEvidence.maximumSamples,
              intervals.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite &&
                  $0.start < $0.end && $0.start < queryEnd && $0.end > queryStart && $0.end <= completedAt }),
              [bedTime, sleepOnset, finalWake, observationEnd].compactMap({ $0 }).allSatisfy({
                  $0.timeIntervalSince1970.isFinite && $0 <= completedAt }),
              let coverage, abs((coverage.asleepMinutes ?? 0) - totalSleepMinutes) < 0.000001,
              observationEnd! >= intervals.map(\.end).max()!,
              finalWake.map({ $0 <= observationEnd! }) ?? true,
              sleepOnset.map({ onset in finalWake.map { onset <= $0 } ?? true }) ?? true else {
            throw DashboardSnapshotError.invalidPayload
        }
        let sorted = intervals.sorted { $0.start < $1.start }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw DashboardSnapshotError.invalidPayload
        }
        if let review {
            guard sessionID == nil, review.episodeID == episodeID, review.treatmentDate == treatmentDate else {
                throw DashboardSnapshotError.invalidPayload
            }
            try review.validate(capturedAt: capturedAt)
        }
    }

    public static func validate(_ episodes: [Self], in snapshot: CloudDashboardSnapshot) throws {
        guard !episodes.isEmpty else { return }
        guard episodes.count <= DashboardSleepEvidence.maximumSamples,
              Set(episodes.map(\.episodeID)).count == episodes.count,
              Set(episodes.compactMap(\.sessionID)).count == episodes.compactMap(\.sessionID).count,
              let packet = try DashboardSleepEvidence.read(from: snapshot) else { throw DashboardSnapshotError.invalidPayload }
        struct Row: Decodable {
            struct Column: Decodable { let type: String; let text: String? }
            let sourceTable: String
            let columns: [String: Column]
            func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
        }
        var local: [Row] = []
        if episodes.contains(where: { $0.sessionID != nil }) {
            for dataset: DashboardDataset in [.sessions, .doseEvents] {
                guard let rows = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else {
                    throw DashboardSnapshotError.incompleteDataset
                }
                local += try JSONDecoder().decode([Row].self, from: rows)
            }
        }
        for episode in episodes {
            try episode.validate(capturedAt: snapshot.capturedAt)
            guard episode.queryStart == packet.queryStart, episode.queryEnd == packet.queryEnd,
                  episode.completedAt == packet.completedAt, episode.timeZoneID == packet.timeZoneID else {
                throw DashboardSnapshotError.invalidPayload
            }
            for interval in episode.intervals {
                let supporting = packet.samples.filter { sample in
                    interval.asleep ? [.asleep, .core, .deep, .rem].contains(sample.stage) : sample.stage == .awake
                }.map { RecordedSleepInterval(start: $0.start, end: $0.end, asleep: interval.asleep) }
                guard let support = SleepIntervalCoverage.calculate(start: interval.start, end: interval.end, intervals: supporting),
                      support.status == .available else { throw DashboardSnapshotError.invalidPayload }
            }
            if let sessionID = episode.sessionID {
                let rows = local.filter { $0.text("session_id") == sessionID }
                guard !rows.isEmpty, rows.allSatisfy({ ["sleep_sessions", "current_session", "dose_events"].contains($0.sourceTable) &&
                    $0.text("session_date") == episode.treatmentDate }) else { throw DashboardSnapshotError.invalidPayload }
            }
        }
    }
}

/// A provider-only review whose private binding was checked by the phone producer.
public struct DashboardSharedProviderDoseReview: Codable, Equatable, Sendable {
    public let episodeID: String
    public let treatmentDate: String
    public let revisionID: UUID
    public let recordedAt: Date
    public let confirmedCount: Int?
    public let historicalPlanCount: Int?
    public let secondNotTaken: Bool?

    public static func project(_ review: DashboardDoseReview, episodeID: String, treatmentDate: String,
                               providerFingerprint: String, capturedAt: Date) -> Self? {
        guard episodeID.hasPrefix("apple-health:"), review.observationID == episodeID,
              review.validationError(now: capturedAt) == nil,
              review.sourceFingerprint == DashboardDoseReview.observationFingerprint(observationID: episodeID,
                sessionDate: treatmentDate, events: [], providerFingerprint: providerFingerprint) else { return nil }
        return .init(episodeID: episodeID, treatmentDate: treatmentDate, revisionID: review.revisionID,
            recordedAt: review.recordedAt, confirmedCount: review.confirmedCount,
            historicalPlanCount: review.historicalPlanCount, secondNotTaken: review.secondNotTaken)
    }
    public func validate(capturedAt: Date) throws {
        guard episodeID.hasPrefix("apple-health:"), DashboardReportingWindow.isValidDateKey(treatmentDate),
              recordedAt.timeIntervalSince1970.isFinite, recordedAt <= capturedAt,
              confirmedCount.map({ (0...2).contains($0) }) ?? true,
              historicalPlanCount.map({ (1...2).contains($0) }) ?? true,
              !(secondNotTaken == true && confirmedCount == 2) else { throw DashboardSnapshotError.invalidPayload }
    }
}
