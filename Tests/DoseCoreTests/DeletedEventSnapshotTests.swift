import XCTest
@testable import DoseCore

final class DeletedEventSnapshotTests: XCTestCase {

    func test_snapshot_roundTripsThroughUndoableAction() async {
        let snapshot = DeletedEventSnapshot(
            id: "abc-123",
            eventType: "bathroom",
            displayName: "Bathroom",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            colorHex: "#FF00AA",
            notes: "test note"
        )

        let action = UndoableAction.deleteEvent(snapshot: snapshot)
        let manager = DoseUndoManager()
        await manager.register(action)

        let pending = await manager.pending
        XCTAssertEqual(pending, action)

        guard case let .deleteEvent(recovered) = pending else {
            XCTFail("Expected .deleteEvent, got \(String(describing: pending))")
            return
        }
        XCTAssertEqual(recovered, snapshot)
    }

    func test_snapshot_equatability() {
        let a = DeletedEventSnapshot(id: "1", eventType: "wake", displayName: "Wake",
                                     timestamp: Date(timeIntervalSince1970: 0))
        let b = DeletedEventSnapshot(id: "1", eventType: "wake", displayName: "Wake",
                                     timestamp: Date(timeIntervalSince1970: 0))
        let c = DeletedEventSnapshot(id: "2", eventType: "wake", displayName: "Wake",
                                     timestamp: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_undoDeleteEvent_withinWindow_succeeds() async {
        var now = Date()
        let manager = DoseUndoManager(windowSeconds: 5.0, now: { now })
        let snapshot = DeletedEventSnapshot(
            id: "evt-1",
            eventType: "bathroom",
            displayName: "Bathroom",
            timestamp: now
        )
        await manager.register(.deleteEvent(snapshot: snapshot))

        now = now.addingTimeInterval(2.0)
        let result = await manager.undo()

        guard case let .success(action) = result,
              case let .deleteEvent(recovered) = action else {
            XCTFail("Expected success with .deleteEvent, got \(result)")
            return
        }
        XCTAssertEqual(recovered, snapshot)
    }

    func test_undoDeleteEvent_afterWindow_expires() async {
        var now = Date()
        let manager = DoseUndoManager(windowSeconds: 5.0, now: { now })
        let snapshot = DeletedEventSnapshot(
            id: "evt-2",
            eventType: "wake_brief",
            displayName: "Brief Wake",
            timestamp: now
        )
        await manager.register(.deleteEvent(snapshot: snapshot))

        now = now.addingTimeInterval(6.0)
        let result = await manager.undo()
        XCTAssertEqual(result, .expired)
    }
}
