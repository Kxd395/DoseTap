import XCTest
@testable import DoseCore

final class SupplyQuantityTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    func source() -> (SupplyBackup, UUID) {
        var value = SupplyBackup()
        let bottle = UUID()
        value.bottleStarts = [.init(id: bottle, openedAt: time, recordedAt: time)]
        return (value, bottle)
    }
    func entry(_ kind: SupplyQuantityKind, _ bottle: UUID, _ amount: Int = 0, offset: Double = 0,
               preparation: UUID? = nil, dose: SupplyDoseEvidence? = nil) -> SupplyQuantityEntry {
        .init(id: UUID(), bottleID: bottle, kind: kind, amountMg: amount,
              occurredAt: time.addingTimeInterval(offset), recordedAt: time.addingTimeInterval(offset),
              reason: "Confirmed test report", preparationID: preparation, dose: dose)
    }
    func testPreparationAndLinkSubtractOnceAndSurviveRoundTrip() throws {
        var (value, bottle) = source()
        XCTAssertNil(value.remainingBottleMg(bottle))
        try value.recordQuantity(entry(.baseline, bottle, 90_000), now: time)
        let first = entry(.preparation, bottle, 4_500, offset: 1)
        let second = entry(.preparation, bottle, 4_500, offset: 1)
        try value.recordQuantities([first, second], now: time.addingTimeInterval(1))
        XCTAssertEqual(value.remainingBottleMg(bottle), 81_000)
        let dose = SupplyDoseEvidence(eventID: "dose-1", sessionID: "night", eventType: "dose1", occurredAt: time.addingTimeInterval(2))
        let link = entry(.doseLink, bottle, offset: 2, preparation: first.id, dose: dose)
        try value.recordQuantity(link, now: time.addingTimeInterval(2))
        try value.recordQuantity(link, now: time.addingTimeInterval(2))
        XCTAssertEqual(value.remainingBottleMg(bottle), 81_000)
        XCTAssertEqual(value.unresolvedPreparations.count, 1)
        try value.recordQuantity(entry(.discard, bottle, offset: 3, preparation: second.id), now: time.addingTimeInterval(3))
        XCTAssertEqual(value.unresolvedPreparations.count, 0)
        XCTAssertEqual(value.remainingBottleMg(bottle), 81_000)
        XCTAssertEqual(try JSONDecoder().decode(SupplyBackup.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(value.version, 3)
    }
    func testFullBottleStartInitializesStandardAmountOnce() throws {
        var value = SupplyBackup()
        let receipt = UUID(), bottle = UUID()
        try value.receiveBottles(id: receipt, count: 3, receivedAt: time, recordedAt: time, now: time)
        try value.startFullXYWAVBottle(id: bottle, receiptID: receipt, openedAt: time, recordedAt: time, now: time)
        XCTAssertEqual(value.remainingBottleMg(bottle), 90_000)
        XCTAssertEqual(value.trackedUnopenedBottleCount, 2)
        XCTAssertEqual(value.quantityEntries?.count, 1)
        try value.recordQuantity(entry(.preparation, bottle, 4_500, offset: 1), now: time.addingTimeInterval(1))
        let prepared = value
        try value.startFullXYWAVBottle(id: bottle, receiptID: receipt, openedAt: time, recordedAt: time, now: time.addingTimeInterval(2))
        XCTAssertEqual(value, prepared)
        XCTAssertEqual(value.remainingBottleMg(bottle), 85_500)
        XCTAssertEqual(try JSONDecoder().decode(SupplyBackup.self, from: JSONEncoder().encode(value)), value)
    }

    func testBalanceDoesNotInventUnopenedStock() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 45_000), now: time)
        XCTAssertEqual(value.remainingBottleMg(bottle), 45_000)
        XCTAssertNil(value.trackedUnopenedBottleCount)
        let restored = try JSONDecoder().decode(SupplyBackup.self, from: JSONEncoder().encode(value))
        XCTAssertNil(restored.trackedUnopenedBottleCount)
    }

    func testFullUnlinkedBottleHasQuantityWithoutInventingDelivery() throws {
        var value = SupplyBackup()
        let bottle = UUID()
        try value.startFullXYWAVBottle(id: bottle, receiptID: nil, openedAt: time, recordedAt: time, now: time)
        XCTAssertEqual(value.remainingBottleMg(bottle), 90_000)
        XCTAssertNil(value.trackedUnopenedBottleCount)
        XCTAssertNil(value.activeBottleStart?.receiptID)
        let before = value
        try value.startFullXYWAVBottle(id: bottle, receiptID: nil, openedAt: time, recordedAt: time, now: time)
        XCTAssertEqual(value, before)
        try value.voidBottleStart(id: bottle, at: time, now: time)
        XCTAssertNil(value.trackedUnopenedBottleCount)
        XCTAssertNil(value.activeBottleStart)
        let receipt = UUID()
        try value.receiveBottles(id: receipt, count: 1, receivedAt: time, recordedAt: time, now: time)
        let tracked = value
        XCTAssertThrowsError(try value.startFullXYWAVBottle(id: UUID(), receiptID: nil, openedAt: time, recordedAt: time, now: time))
        XCTAssertEqual(value, tracked, "Known stock requires choosing its receipt, not bypassing the count")
    }

    func testFullBottleStartFailureDoesNotCreateOpeningOrRefillLegacyBottle() throws {
        var value = SupplyBackup()
        let receipt = UUID(), bottle = UUID()
        try value.receiveBottles(id: receipt, count: 3, receivedAt: time, recordedAt: time, now: time)
        let before = value
        XCTAssertThrowsError(try value.startFullXYWAVBottle(id: bottle, receiptID: UUID(), openedAt: time, recordedAt: time, now: time))
        XCTAssertThrowsError(try value.startFullXYWAVBottle(id: bottle, receiptID: receipt, openedAt: time.addingTimeInterval(1), recordedAt: time, now: time))
        XCTAssertEqual(value, before)
        try value.startBottle(id: bottle, receiptID: receipt, openedAt: time, recordedAt: time, now: time)
        let legacy = value
        XCTAssertThrowsError(try value.startFullXYWAVBottle(id: bottle, receiptID: receipt, openedAt: time, recordedAt: time, now: time))
        XCTAssertEqual(value, legacy)
        XCTAssertNil(value.remainingBottleMg(bottle))
        let conflictingID = UUID()
        var baseline = entry(.baseline, bottle, 90_000); baseline.id = conflictingID
        try value.recordQuantity(baseline, now: time)
        let beforeConflict = value, later = time.addingTimeInterval(1)
        XCTAssertThrowsError(try value.startFullXYWAVBottle(id: conflictingID, receiptID: receipt, openedAt: later, recordedAt: later, now: later))
        XCTAssertEqual(value, beforeConflict, "A baseline conflict must also roll back the new opening and stock count")
    }

    func testUndoUnusedFullOpeningVoidsItsAutomaticBaselineOnly() throws {
        var value = SupplyBackup()
        let receipt = UUID(), bottle = UUID()
        try value.receiveBottles(id: receipt, count: 3, receivedAt: time, recordedAt: time, now: time)
        try value.startFullXYWAVBottle(id: bottle, receiptID: receipt, openedAt: time, recordedAt: time, now: time)
        let prep = entry(.preparation, bottle, 4_500, offset: 1)
        try value.recordQuantity(prep, now: time.addingTimeInterval(1))
        let before = value
        XCTAssertThrowsError(try value.voidBottleStart(id: bottle, at: time.addingTimeInterval(2), now: time.addingTimeInterval(2)))
        XCTAssertEqual(value, before)
        try value.voidQuantity(id: prep.id, at: time.addingTimeInterval(2), now: time.addingTimeInterval(2))
        try value.voidBottleStart(id: bottle, at: time.addingTimeInterval(3), now: time.addingTimeInterval(3))
        XCTAssertNil(value.activeBottleStart)
        XCTAssertNil(value.remainingBottleMg(bottle))
        XCTAssertEqual(value.trackedUnopenedBottleCount, 3)
        XCTAssertEqual(value.quantityEntries?.count, 2)
        XCTAssertTrue(value.quantityEntries?.allSatisfy { $0.voidedAt != nil } == true)
    }
    func testAtomicInsufficientStockAndExplicitZero() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 4_500), now: time)
        let before = value
        XCTAssertThrowsError(try value.recordQuantities([entry(.preparation, bottle, 4_500), entry(.preparation, bottle, 4_500)], now: time))
        XCTAssertEqual(value, before)
        try value.recordQuantity(entry(.preparation, bottle, 4_500), now: time)
        XCTAssertEqual(value.remainingBottleMg(bottle), 0)
    }
    func testPreparationLimitDoesNotAutoResolveOrEraseHistoricalUse() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 90_000), now: time)
        let prep = entry(.preparation, bottle, 4_500)
        try value.recordQuantity(prep, now: time)
        XCTAssertFalse(prep.preparationLimitReached(at: time.addingTimeInterval(86_399)))
        XCTAssertTrue(prep.preparationLimitReached(at: time.addingTimeInterval(86_400)))
        XCTAssertEqual(value.unresolvedPreparations.count, 1)
        let dose = SupplyDoseEvidence(eventID: "late", sessionID: "next", eventType: "dose1", occurredAt: time.addingTimeInterval(90_000))
        try value.recordQuantity(entry(.doseLink, bottle, offset: 90_000, preparation: prep.id, dose: dose), now: time.addingTimeInterval(90_000))
        XCTAssertEqual(value.remainingBottleMg(bottle), 85_500)
    }
    func testInvalidImportsDuplicateDoseAndDependentUndoFailClosed() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 90_000), now: time)
        let prep = entry(.preparation, bottle, 4_500)
        try value.recordQuantity(prep, now: time)
        let dose = SupplyDoseEvidence(eventID: "taken", sessionID: "night", eventType: "dose2", occurredAt: time)
        let link = entry(.doseLink, bottle, preparation: prep.id, dose: dose)
        try value.recordQuantity(link, now: time)
        XCTAssertThrowsError(try value.voidQuantity(id: prep.id, at: time, now: time))
        var malformed = value; malformed.version = 2
        XCTAssertFalse(malformed.isValid)
        malformed = value; malformed.quantityEntries![1].amountMg = Int.max
        XCTAssertFalse(malformed.isValid)
        try value.voidQuantity(id: link.id, at: time, now: time)
        try value.voidQuantity(id: prep.id, at: time, now: time)
        XCTAssertEqual(value.remainingBottleMg(bottle), 90_000)
        XCTAssertEqual(value.quantityEntries?.count, 3)
    }
    func testReconciliationAndLaterReceiptDoNotDowngradeOrEraseQuantities() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 90_000), now: time)
        try value.recordQuantity(entry(.preparation, bottle, 4_500, offset: 1), now: time.addingTimeInterval(1))
        try value.recordQuantity(entry(.baseline, bottle, 70_000, offset: 2), now: time.addingTimeInterval(2))
        XCTAssertEqual(value.remainingBottleMg(bottle), 70_000)
        XCTAssertThrowsError(try value.recordQuantity(entry(.preparation, bottle, 500), now: time.addingTimeInterval(3)))
        try value.receiveBottles(id: UUID(), count: 3, receivedAt: time, recordedAt: time, now: time)
        XCTAssertEqual(value.version, 3)
        XCTAssertTrue(value.isValid)
    }

    func testDuplicateDoseAllocationAndWrongBottleResolutionAreRejected() throws {
        var (value, bottle) = source()
        try value.recordQuantity(entry(.baseline, bottle, 90_000), now: time)
        let first = entry(.preparation, bottle, 4_500), second = entry(.preparation, bottle, 4_500)
        try value.recordQuantities([first, second], now: time)
        let dose = SupplyDoseEvidence(eventID: "one-dose", sessionID: "night", eventType: "dose2", occurredAt: time)
        try value.recordQuantity(entry(.doseLink, bottle, preparation: first.id, dose: dose), now: time)
        let original = value
        XCTAssertThrowsError(try value.recordQuantity(entry(.doseLink, bottle, preparation: second.id, dose: dose), now: time))
        XCTAssertThrowsError(try value.recordQuantity(entry(.discard, UUID(), preparation: second.id), now: time))
        XCTAssertEqual(value, original)
    }

    func testFutureAndInvalidDatesCannotInitializeOrResolveStock() throws {
        var (value, bottle) = source()
        XCTAssertThrowsError(try value.recordQuantity(entry(.baseline, bottle, 90_001), now: time))
        XCTAssertThrowsError(try value.recordQuantity(entry(.baseline, bottle, 90_000, offset: 1), now: time))
        XCTAssertThrowsError(try value.recordQuantity(entry(.baseline, bottle, 90_000, offset: -1), now: time))
        XCTAssertThrowsError(try value.recordQuantity(entry(.preparation, bottle, 4_500), now: time))
        XCTAssertNil(value.quantityEntries)
        try value.recordQuantity(entry(.baseline, bottle, 0), now: time)
        let before = value
        XCTAssertThrowsError(try value.voidQuantity(id: value.quantityEntries![0].id, at: time.addingTimeInterval(-1), now: time))
        XCTAssertEqual(value, before)
    }
}
