import Foundation

/// User-reviewed observation bounds, not measured sleep or final awakening.
public struct ReviewedSleepWindow: Codable, Hashable, Sendable {
    public let version: Int
    public let source: String
    public let sessionID: String
    public let start: Date
    public let end: Date
    public let reviewedAt: Date
    public let entryTimeZoneID: String
    public let startUTCOffsetSeconds: Int
    public let endUTCOffsetSeconds: Int

    public init(sessionID: String, start: Date, end: Date, entryTimeZone: TimeZone, reviewedAt: Date) {
        version = 1; source = "user_reviewed"
        self.sessionID = sessionID; self.start = start; self.end = end; self.reviewedAt = reviewedAt
        entryTimeZoneID = entryTimeZone.identifier
        startUTCOffsetSeconds = start.timeIntervalSinceReferenceDate.isFinite ? entryTimeZone.secondsFromGMT(for: start) : 0
        endUTCOffsetSeconds = end.timeIntervalSinceReferenceDate.isFinite ? entryTimeZone.secondsFromGMT(for: end) : 0
    }

    public func validationError(now: Date) -> String? {
        guard version == 1, source == "user_reviewed",
              !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TimeZone(identifier: entryTimeZoneID) != nil,
              TimeZone(secondsFromGMT: startUTCOffsetSeconds) != nil,
              TimeZone(secondsFromGMT: endUTCOffsetSeconds) != nil else {
            return "The saved night window's identity or entry information needs review."
        }
        guard [start, end, reviewedAt, now].allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              end.timeIntervalSince(start).isFinite, start < end,
              end <= reviewedAt, reviewedAt <= now else {
            return "Choose a window that ends after it starts and no later than its review time."
        }
        return nil
    }
}

/// Local boundary checks only. Recompute after any source change; this is not sleep coverage.
public struct ReviewedWindowAssessment: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case missing, checked, needsReview }
    public enum Reason: String, Codable, CaseIterable, Sendable {
        case invalidWindow, invalidDoseRecords, doseOutsideWindow, overlappingWindow
        case overlappingNap, incompleteNap, ambiguousNap, unreadableEvidence
    }
    public struct NapMarker: Sendable {
        public let id: String
        public let group: String
        public let timestamp: Date
        public let isStart: Bool
        public init(id: String, group: String, timestamp: Date, isStart: Bool) {
            self.id = id; self.group = group; self.timestamp = timestamp; self.isStart = isStart
        }
    }
    public let derivationVersion: String
    public let status: Status
    public let reasons: [Reason]
    public let assessedAt: Date?

    private init(status: Status, reasons: [Reason], now: Date) {
        derivationVersion = "reviewed_window_assessment_v1"
        self.status = status; self.reasons = reasons
        assessedAt = now.timeIntervalSinceReferenceDate.isFinite ? now : nil
    }
    public static func unavailable(now: Date) -> Self {
        .init(status: .needsReview, reasons: [.unreadableEvidence], now: now)
    }
    public static func calculate(window: ReviewedSleepWindow?, sessionID: String, doses: [StoredDoseEvent],
                                 otherWindows: [ReviewedSleepWindow], naps: [NapMarker], now: Date) -> Self {
        guard let window else { return .init(status: .missing, reasons: [], now: now) }
        guard window.validationError(now: now) == nil, window.sessionID == sessionID else {
            return .init(status: .needsReview, reasons: [.invalidWindow], now: now)
        }
        var reasons = Set<Reason>()
        func overlaps(_ start: Date, _ end: Date) -> Bool { start < window.end && end > window.start }
        let taken = doses.filter { ["dose1", "dose2", "extra_dose"].contains($0.eventType) }
        let first = taken.filter { $0.eventType == "dose1" }, second = taken.filter { $0.eventType == "dose2" }
        let skipped = doses.filter { $0.eventType == "dose2_skipped" }
        let extras = taken.filter { $0.eventType == "extra_dose" }
        if first.count > 1 || second.count + skipped.count > 1 ||
            ((!second.isEmpty || !skipped.isEmpty || !extras.isEmpty) && first.count != 1) ||
            (!extras.isEmpty && second.count != 1) { reasons.insert(.invalidDoseRecords) }
        for dose in taken {
            if !dose.timestamp.timeIntervalSinceReferenceDate.isFinite || dose.timestamp > now ||
                (dose.eventType != "dose1" && first.first.map { dose.timestamp < $0.timestamp } == true) ||
                (dose.eventType == "extra_dose" && second.first.map { dose.timestamp < $0.timestamp } == true) {
                reasons.insert(.invalidDoseRecords)
            } else if dose.timestamp < window.start || dose.timestamp >= window.end {
                reasons.insert(.doseOutsideWindow)
            }
        }
        for other in otherWindows where other != window {
            if other.validationError(now: now) != nil || other.sessionID == sessionID {
                reasons.insert(.invalidWindow)
            } else if overlaps(other.start, other.end) { reasons.insert(.overlappingWindow) }
        }
        let validNaps = naps.filter {
            !$0.id.isEmpty && !$0.group.isEmpty && $0.timestamp.timeIntervalSinceReferenceDate.isFinite && $0.timestamp <= now
        }
        if validNaps.count != naps.count { reasons.insert(.unreadableEvidence) }
        for group in Dictionary(grouping: validNaps, by: \.group).values {
            let sorted = group.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                if $0.isStart != $1.isStart { return $0.isStart } // Equal endpoints cannot invent a positive nap.
                return $0.id < $1.id
            }
            var starts: [Date] = []
            for marker in sorted {
                if marker.isStart { starts.append(marker.timestamp); continue }
                if let start = starts.first {
                    if start == marker.timestamp && start >= window.start && start < window.end {
                        reasons.insert(.ambiguousNap)
                    } else if overlaps(start, marker.timestamp) {
                        reasons.insert(starts.count == 1 ? .overlappingNap : .ambiguousNap)
                    }
                    starts.removeAll()
                } else if marker.timestamp > window.start { reasons.insert(.incompleteNap) }
            }
            if let start = starts.first, start < window.end { reasons.insert(.incompleteNap) }
        }
        let ordered = Reason.allCases.filter { reasons.contains($0) }
        return .init(status: ordered.isEmpty ? .checked : .needsReview, reasons: ordered, now: now)
    }
}
