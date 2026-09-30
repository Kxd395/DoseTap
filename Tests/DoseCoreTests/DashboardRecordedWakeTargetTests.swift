import XCTest
@testable import DoseCore

final class DashboardRecordedWakeTargetTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    func event(id: String = "dose", revision: UUID, wake: Double = 600, session: String = "s") throws -> StoredDoseEvent {
        let warning = WorkWakeWarning(sessionId: session, revision: revision, wakeDate: "2026-09-21",
            timeZoneIdentifier: "UTC", requiredWake: base.addingTimeInterval(wake), targetAt: base, target: .doseTarget)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(warning))
        let metadata = String(decoding: try JSONSerialization.data(withJSONObject: ["work_warning_acknowledgement": payload]), as: UTF8.self)
        return .init(id: id, eventType: "dose2", timestamp: base, sessionDate: "2026-09-21", metadata: metadata, sessionId: session)
    }
    func testSavedWarningKeepsHistoricalTargetAndEverySourceID() throws {
        let revision = UUID()
        let result = DashboardRecordedWakeTarget.derive(sessionID: "s", events: [try event(revision: revision), try event(id: "extra", revision: revision)], asOf: base.addingTimeInterval(100))
        XCTAssertEqual(result.state, .available); XCTAssertEqual(result.requiredWake, base.addingTimeInterval(600))
        XCTAssertEqual(Set(result.sources.map(\.eventID)), ["dose", "extra"])
        XCTAssertEqual(result.sources.first?.revision, revision)
        XCTAssertEqual(result.sources.first?.sessionID, "s")
    }
    func testMissingConflictingAndForeignWarningsStayDistinct() throws {
        XCTAssertEqual(DashboardRecordedWakeTarget.derive(sessionID: "s", events: [], asOf: base).state, .unavailable)
        let conflict = DashboardRecordedWakeTarget.derive(sessionID: "s", events: [try event(revision: UUID()), try event(id: "other", revision: UUID(), wake: 700)], asOf: base)
        XCTAssertEqual(conflict.state, .needsReview); XCTAssertNil(conflict.requiredWake)
        XCTAssertEqual(conflict.sources.count, 2)
        let foreign = DashboardRecordedWakeTarget.derive(sessionID: "s", events: [try event(revision: UUID(), session: "foreign")], asOf: base)
        XCTAssertEqual(foreign.state, .needsReview); XCTAssertNil(foreign.requiredWake)
    }
}
