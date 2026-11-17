import XCTest
@testable import DoseCore

final class SupplyBottleTrackingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let clock = Date(timeIntervalSince1970: 1_700_001_000)

    func testLegacyRoundTripDoesNotInventReceiptOrAssignBottle() throws {
        var value = SupplyBackup()
        value.bottleStarts = [SupplyBottleStart(openedAt: date, recordedAt: date)]
        let restored = try JSONDecoder().decode(SupplyBackup.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        XCTAssertTrue(restored.isValid)
        XCTAssertNil(restored.receipts)
        XCTAssertNil(restored.trackedUnopenedBottleCount)
        XCTAssertNil(restored.currentReceiptOrdinal)
        XCTAssertEqual(restored.activeBottleStart, value.bottleStarts.first)
    }

    func testReceiptDoesNotOpenBottleAndMultipleShipmentsRetainStock() throws {
        var value = SupplyBackup()
        let first = UUID(), second = UUID()
        try value.receiveBottles(id: first, count: 3, receivedAt: date, recordedAt: date, now: clock)
        XCTAssertNil(value.activeBottleStart)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 3)
        try value.startBottle(id: UUID(), receiptID: first, openedAt: date, recordedAt: date, now: clock)
        XCTAssertEqual(value.currentReceiptOrdinal, 1)
        try value.receiveBottles(id: second, count: 2, receivedAt: date, recordedAt: date, now: clock)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 4)
        XCTAssertEqual(value.activeBottleStart?.receiptID, first)
        let restored = try JSONDecoder().decode(SupplyBackup.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        XCTAssertEqual(restored.version, 2)
        XCTAssertTrue(restored.isValid)
    }

    func testRetryUsesStableIdentityAndRejectsConflictingPayloadWithoutMutation() throws {
        var value = SupplyBackup()
        let receipt = UUID(), opening = UUID()
        try value.receiveBottles(id: receipt, count: 3, receivedAt: date, recordedAt: date, now: clock)
        try value.receiveBottles(id: receipt, count: 3, receivedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: opening, receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: opening, receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        XCTAssertEqual(value.receipts?.count, 1)
        XCTAssertEqual(value.bottleStarts.count, 1)
        let before = value
        XCTAssertThrowsError(try value.receiveBottles(id: receipt, count: 4, receivedAt: date, recordedAt: date, now: clock))
        XCTAssertThrowsError(try value.startBottle(id: opening, receiptID: receipt, openedAt: date.addingTimeInterval(-1), recordedAt: date, now: clock))
        XCTAssertEqual(value, before)
    }

    func testUndoRetainsHistoryRestoresPreviousOpeningAndReturnsTrackedStock() throws {
        var value = SupplyBackup()
        let receipt = UUID(), first = UUID(), second = UUID()
        try value.receiveBottles(id: receipt, count: 2, receivedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: first, receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: second, receiptID: receipt, openedAt: date.addingTimeInterval(1), recordedAt: date.addingTimeInterval(1), now: clock)
        XCTAssertEqual(value.activeBottleStart?.id, second)
        XCTAssertEqual(value.currentReceiptOrdinal, 2)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 0)
        XCTAssertThrowsError(try value.voidBottleStart(id: first, at: date, now: clock))
        XCTAssertThrowsError(try value.voidReceipt(id: receipt, at: date, now: clock))
        try value.voidBottleStart(id: second, at: date.addingTimeInterval(2), now: clock)
        try value.voidBottleStart(id: second, at: date.addingTimeInterval(2), now: clock)
        XCTAssertEqual(value.activeBottleStart?.id, first)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 1)
        try value.voidBottleStart(id: first, at: date.addingTimeInterval(2), now: clock)
        try value.voidReceipt(id: receipt, at: date.addingTimeInterval(2), now: clock)
        XCTAssertEqual(value.bottleStarts.count, 2)
        XCTAssertEqual(value.receipts?.count, 1)
        XCTAssertNotNil(value.receipts?.first?.voidedAt)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 0)
        XCTAssertTrue(value.isValid)
    }

    func testInvalidCommandsFailAtomicallyIncludingExhaustionAndFutureTime() throws {
        var value = SupplyBackup()
        for count in [0, 101] {
            XCTAssertThrowsError(try value.receiveBottles(id: UUID(), count: count, receivedAt: date, recordedAt: date, now: clock))
        }
        XCTAssertEqual(value, SupplyBackup())
        let receipt = UUID()
        try value.receiveBottles(id: receipt, count: 1, receivedAt: date, recordedAt: date, now: clock)
        let before = value
        XCTAssertThrowsError(try value.startBottle(id: UUID(), receiptID: UUID(), openedAt: date, recordedAt: date, now: clock))
        XCTAssertThrowsError(try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date.addingTimeInterval(-1), recordedAt: date, now: clock))
        XCTAssertThrowsError(try value.receiveBottles(id: UUID(), count: 1, receivedAt: Date.distantFuture, recordedAt: Date.distantFuture, now: clock))
        XCTAssertEqual(value, before)
        try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        let exhausted = value
        XCTAssertThrowsError(try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date, recordedAt: date, now: clock))
        XCTAssertEqual(value, exhausted)
    }

    func testImportedInvalidLinksAndVersionDowngradeAreRejected() throws {
        var value = SupplyBackup()
        let receipt = UUID()
        try value.receiveBottles(id: receipt, count: 1, receivedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        value.version = 1
        XCTAssertFalse(value.isValid)
        value.version = 2
        value.bottleStarts[0].receiptID = UUID()
        XCTAssertFalse(value.isValid)
        value.bottleStarts[0].receiptID = receipt
        value.receipts?[0].voidedAt = date
        XCTAssertFalse(value.isValid)
    }
    func testUnassignedOpeningDoesNotClaimTrackedStockAndInvalidImportsFailClosed() throws {
        var value = SupplyBackup()
        let receipt = UUID()
        try value.receiveBottles(id: receipt, count: 1, receivedAt: date, recordedAt: date, now: clock)
        try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date, recordedAt: date, now: clock)
        let later = date.addingTimeInterval(1)
        value.bottleStarts.append(SupplyBottleStart(openedAt: later, recordedAt: later))
        XCTAssertTrue(value.isValid)
        XCTAssertNil(value.activeBottleStart?.receiptID)
        XCTAssertNil(value.currentReceiptOrdinal)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 0)
        let valid = value
        value.bottleStarts[1].receiptID = receipt
        XCTAssertFalse(value.isValid) // More openings than received bottles.
        value = valid
        value.bottleStarts[1].openedAt = date
        XCTAssertFalse(value.isValid) // Ambiguous simultaneous current bottles.
        value = valid
        value.bottleStarts[1].voidedAt = date
        XCTAssertFalse(value.isValid) // Undo cannot predate its source record.
    }

    func testLegacyDuplicateOpeningDatesSurviveTrackingUpgrade() throws {
        var value = SupplyBackup()
        value.bottleStarts = (0..<2).map { _ in SupplyBottleStart(openedAt: date, recordedAt: date) }
        let legacy = value.bottleStarts
        XCTAssertTrue(value.isValid)
        let receipt = UUID()
        try value.receiveBottles(id: receipt, count: 3, receivedAt: date, recordedAt: date, now: clock)
        XCTAssertTrue(value.isValid)
        XCTAssertEqual(value.bottleStarts, legacy)
        XCTAssertNil(value.currentReceiptOrdinal)
        XCTAssertThrowsError(try value.startBottle(id: UUID(), receiptID: receipt, openedAt: date, recordedAt: date, now: clock))
        let later = date.addingTimeInterval(1)
        try value.startBottle(id: UUID(), receiptID: receipt, openedAt: later, recordedAt: later, now: clock)
        XCTAssertEqual(value.currentReceiptOrdinal, 1)
    }

}
