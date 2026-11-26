import XCTest
@testable import DoseCore

final class WorkPlanSnapshotTests: XCTestCase {
    func testCapturedPlanIgnoresLaterBackdatedCancellation() throws {
        let recorded = Date(timeIntervalSince1970: 1_790_000_000)
        let captured = recorded.addingTimeInterval(100)
        var value = WorkContextDocument()
        value.rosters = [.init(effectiveFrom: "2026-09-01", effectiveTo: "2026-10-31", timeZoneIdentifier: "UTC", weekdays: [3,4,5], recordedAt: recorded)]
        let priorRevision = value.revision
        let snapshot = try XCTUnwrap(value.capturePlan(preSleepLogID: "pre-1", sessionID: nil, at: captured))
        XCTAssertEqual(snapshot.contextRevision, priorRevision)
        XCTAssertEqual(value.schemaVersion, 2)
        XCTAssertEqual(snapshot.rosterCount, 1)
        value.occurrences.append(.init(workDate: "2026-09-22", timeZoneIdentifier: "UTC", plannedWorking: false, recordedAt: recorded))
        var association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "UTC", plannedAt: captured, recordedAt: captured)
        XCTAssertEqual(value.capturePlan(preSleepLogID: "pre-1", sessionID: nil, at: captured.addingTimeInterval(1))?.id, snapshot.id)
        association.planSnapshotID = snapshot.id
        XCTAssertEqual(value.classify(association, basis: .planned, asOf: captured).phase, .entering)
        association.planSnapshotID = nil
        XCTAssertEqual(value.classify(association, basis: .planned, asOf: captured).phase, .off)
    }
    func testMissingSnapshotAndInvalidCaptureRemainUnknown() {
        var value = WorkContextDocument()
        XCTAssertNil(value.capturePlan(preSleepLogID: "", sessionID: nil, at: Date()))
        var association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "UTC", plannedAt: Date(timeIntervalSince1970: 100), recordedAt: Date(timeIntervalSince1970: 100))
        association.planSnapshotID = UUID()
        XCTAssertEqual(value.classify(association, basis: .planned, asOf: Date()).phase, .unknown)
    }
    func testCaptureAtHistoryLimitDoesNotMutateDocument() {
        var value = WorkContextDocument(); value.schemaVersion = 2
        value.planSnapshots = (0..<50000).map { WorkPlanSnapshot(preSleepLogID: String($0), sessionID: nil, capturedAt: Date(timeIntervalSince1970: 100), contextRevision: value.revision, rosterCount: 0, occurrenceCount: 0) }
        let revision = value.revision
        XCTAssertNil(value.capturePlan(preSleepLogID: "overflow", sessionID: nil, at: Date()))
        XCTAssertEqual(value.planSnapshots?.count, 50000); XCTAssertEqual(value.revision, revision)
    }

}
