import Foundation
import DoseCore

enum InsightDoseEventKind: String, Sendable {
    case dose1
    case dose2
    case dose2Skipped
    case snooze
    case other

    init(eventType: EventType) {
        switch eventType {
        case .dose1_taken:
            self = .dose1
        case .dose2_taken:
            self = .dose2
        case .dose2_skipped:
            self = .dose2Skipped
        case .dose2_snoozed, .snooze:
            self = .snooze
        default:
            self = .other
        }
    }
}

struct InsightEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: EventType
    let kind: InsightDoseEventKind
    let timestamp: Date
    let details: String?
}
