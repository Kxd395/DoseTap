import Foundation

/// Historical evidence only. Live work/wake preferences cannot populate this projection.
public struct DashboardRecordedWakeTarget: Codable, Equatable, Sendable {
    public static let version = "recorded_required_wake_v1"
    public struct Source: Codable, Equatable, Sendable {
        public let eventID: String
        public let eventOccurredAt: Date
        public let sessionID: String
        public let eventSessionID: String?
        public let revision: UUID
        public let requiredWake: Date
        public let timeZoneID: String
    }
    public let derivationVersion: String
    public let state: DashboardMetricState
    public let reason: String
    public let sources: [Source]
    public var requiredWake: Date? { state == .available ? sources.first?.requiredWake : nil }

    public static func derive(sessionID: String, events: [StoredDoseEvent], asOf: Date) -> Self {
        var sources: [Source] = []
        var invalid = sessionID.isEmpty || !asOf.timeIntervalSinceReferenceDate.isFinite
        for event in events {
            guard let metadata = event.metadata else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any] else {
                invalid = true; continue
            }
            guard let encoded = object["work_warning_acknowledgement"] else { continue }
            guard JSONSerialization.isValidJSONObject(encoded),
                  let data = try? JSONSerialization.data(withJSONObject: encoded),
                  let warning = try? JSONDecoder().decode(WorkWakeWarning.self, from: data) else {
                invalid = true; continue
            }
            let source = Source(eventID: event.id, eventOccurredAt: event.timestamp, sessionID: warning.sessionId,
                eventSessionID: event.sessionId, revision: warning.revision, requiredWake: warning.requiredWake,
                timeZoneID: warning.timeZoneIdentifier)
            if !sources.contains(source) { sources.append(source) }
            if event.id.isEmpty || event.sessionId != sessionID || warning.sessionId != sessionID ||
                !event.timestamp.timeIntervalSinceReferenceDate.isFinite || event.timestamp > asOf ||
                !warning.requiredWake.timeIntervalSinceReferenceDate.isFinite ||
                !warning.targetAt.timeIntervalSinceReferenceDate.isFinite || TimeZone(identifier: warning.timeZoneIdentifier) == nil {
                invalid = true
            }
        }
        if Dictionary(grouping: sources, by: \.eventID).values.contains(where: { $0.count > 1 }) { invalid = true }
        sources.sort { $0.eventID == $1.eventID ? $0.revision.uuidString < $1.revision.uuidString : $0.eventID < $1.eventID }
        if let first = sources.first, !sources.allSatisfy({ $0.revision == first.revision &&
            $0.requiredWake == first.requiredWake && $0.timeZoneID == first.timeZoneID && $0.sessionID == first.sessionID }) {
            invalid = true
        }
        return .init(derivationVersion: version, state: invalid ? .needsReview : sources.isEmpty ? .unavailable : .available,
            reason: invalid ? "Saved wake targets, revisions or source identity require review" : sources.isEmpty
                ? "No historical required-wake acknowledgement was recorded" : "Saved required wake; distinct from actual final awakening",
            sources: sources)
    }
}
