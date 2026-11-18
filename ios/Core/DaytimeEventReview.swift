import Foundation

public struct DaytimeEventReview: Codable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case notReviewed = "Not reviewed", noneReported = "No events reported", eventsReported = "Events reported", unsure = "Unsure"
    }
    public let from: Date
    public let to: Date
    public let status: Status
    public let eventIDs: [UUID]
    public init(from: Date, to: Date, status: Status, eventIDs: [UUID] = []) throws {
        self.from = from; self.to = to; self.status = status; self.eventIDs = eventIDs.sorted { $0.uuidString < $1.uuidString }; try validate()
    }
    public func validate() throws {
        guard from.timeIntervalSince1970.isFinite, to.timeIntervalSince1970.isFinite, from <= to,
              Set(eventIDs).count == eventIDs.count,
              status == .eventsReported ? !eventIDs.isEmpty : eventIDs.isEmpty else { throw DaytimeDiaryError.invalid }
    }
}
