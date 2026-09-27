import Foundation

public enum DashboardDiaryExclusion: String, CaseIterable, Sendable {
    case missingDiary = "No recorded night-outcome diary"
    case unavailableDiary = "Diary unavailable or conflicting"
    case missingPair = "No dose records for this date"
    case unusablePair = "Dose pair missing, skipped or conflicting"
    case identityUnavailable = "Durable dose/diary identity unavailable"
    case identityMismatch = "Dose and diary identities differ"
    case missingFinalWake = "Reported final wake missing"
    case wakeBeforeDose = "Reported final wake precedes Dose 2"
    case missingTimedRating = "Timed sleepiness rating missing"
    case assessmentBeforeDose = "Sleepiness assessment precedes Dose 2"
    case assessmentBeforeWake = "Sleepiness assessment precedes reported final wake"
}

public struct DashboardDiaryPoint: Identifiable, Sendable {
    public var id: String { treatmentDate }
    public let treatmentDate: String
    public let outcomeSessionID: String?
    public let outcomeSourceRecordID: String?
    public let recordedAt: Date?
    public let reportedFinalWakeAt: Date?
    public let sleepiness0To10: Int?
    public let sleepinessAssessedAt: Date?
    public let dose2At: Date?
    public let pairedIntervalMinutes: Double?
    public let dose2ToReportedFinalWakeMinutes: Double?
    public let matchedSleepiness0To10: Int?
    public let elapsedExclusion: DashboardDiaryExclusion?
    public let sleepinessExclusion: DashboardDiaryExclusion?
}

public struct DashboardDiarySummary: Sendable {
    public let elapsedCount: Int
    public let medianElapsedMinutes: Double?
    public let sleepinessCount: Int
    public let medianSleepiness: Double?
    public let elapsedExclusions: [DashboardDiaryExclusion: Int]
    public let sleepinessExclusions: [DashboardDiaryExclusion: Int]
}

/// Descriptive diary evidence, not measured sleep or treatment effectiveness.
/// Both projections always come from the same immutable input generation.
public struct DashboardDiaryAnalysis: Sendable {
    public let sourceID: String
    public let sequence: UInt64
    public let capturedAt: Date
    public let points: [DashboardDiaryPoint]

    public init(snapshot: CloudDashboardSnapshot, now: Date) throws {
        let doses = try DashboardReportProjection(snapshot: snapshot, now: now)
        let questionnaires = try DashboardQuestionnaireProjection(snapshot: snapshot, now: now)
        sourceID = snapshot.sourceID; sequence = snapshot.sequence; capturedAt = snapshot.capturedAt
        let byDate = Dictionary(uniqueKeysWithValues: doses.doseDays.map { ($0.treatmentDate, $0) })
        points = questionnaires.days.map { day in
            let dose = byDate[day.treatmentDate]
            var reason: DashboardDiaryExclusion?
            if day.nightOutcome == .missing { reason = .missingDiary }
            else if day.nightOutcome != .recorded { reason = .unavailableDiary }
            else if dose == nil { reason = .missingPair }
            else if dose?.state != .paired { reason = .unusablePair }
            else if dose?.doseSessionID == nil || day.outcomeSessionID == nil { reason = .identityUnavailable }
            else if dose?.doseSessionID != day.outcomeSessionID { reason = .identityMismatch }
            let joined = reason == nil
            var elapsed: Double?, score: Int?
            if joined {
                if let wake = day.reportedFinalWakeAt, let d2 = dose?.dose2At {
                    let seconds = wake.timeIntervalSince(d2)
                    if seconds.isFinite && seconds >= 0 { elapsed = seconds / 60 }
                    else { reason = .wakeBeforeDose }
                } else { reason = .missingFinalWake }
            }
            let elapsedReason = reason
            if reason == nil {
                if let rating = day.sleepiness0To10, let assessed = day.sleepinessAssessedAt,
                   let d2 = dose?.dose2At, let wake = day.reportedFinalWakeAt {
                    if assessed < d2 { reason = .assessmentBeforeDose }
                    else if assessed < wake { reason = .assessmentBeforeWake }
                    else { score = rating }
                } else { reason = .missingTimedRating }
            }
            return DashboardDiaryPoint(treatmentDate: day.treatmentDate,
                outcomeSessionID: day.outcomeSessionID, outcomeSourceRecordID: day.outcomeSourceRecordID,
                recordedAt: day.outcomeRecordedAt, reportedFinalWakeAt: day.reportedFinalWakeAt,
                sleepiness0To10: day.sleepiness0To10, sleepinessAssessedAt: day.sleepinessAssessedAt,
                dose2At: joined ? dose?.dose2At : nil, pairedIntervalMinutes: joined ? dose?.intervalMinutes : nil,
                dose2ToReportedFinalWakeMinutes: elapsed, matchedSleepiness0To10: score,
                elapsedExclusion: elapsedReason, sleepinessExclusion: reason)
        }
    }

    public static func summaries(for points: [DashboardDiaryPoint]) -> DashboardDiarySummary {
        let elapsed = points.compactMap(\.dose2ToReportedFinalWakeMinutes)
        let scores = points.compactMap(\.matchedSleepiness0To10).map(Double.init)
        func counts(_ reasons: [DashboardDiaryExclusion]) -> [DashboardDiaryExclusion: Int] {
            Dictionary(grouping: reasons, by: { $0 }).mapValues(\.count)
        }
        func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted(); guard !sorted.isEmpty else { return nil }
            return sorted[(sorted.count - 1) / 2] / 2 + sorted[sorted.count / 2] / 2
        }
        return .init(elapsedCount: elapsed.count, medianElapsedMinutes: median(elapsed),
            sleepinessCount: scores.count, medianSleepiness: median(scores),
            elapsedExclusions: counts(points.compactMap(\.elapsedExclusion)),
            sleepinessExclusions: counts(points.compactMap(\.sleepinessExclusion)))
    }
}
