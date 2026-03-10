import XCTest
@testable import DoseCore

// MARK: - AmountUnit Tests

final class AmountUnitTests: XCTestCase {

    // MARK: - toMilligrams

    func test_mg_identity() {
        XCTAssertEqual(AmountUnit.mg.toMilligrams(value: 250), 250)
    }

    func test_g_to_mg() {
        XCTAssertEqual(AmountUnit.g.toMilligrams(value: 4.5), 4500)
    }

    func test_mcg_to_mg() {
        let result = AmountUnit.mcg.toMilligrams(value: 500)!
        XCTAssertEqual(result, 0.5, accuracy: 0.0001)
    }

    func test_mL_needs_concentration() {
        XCTAssertNil(AmountUnit.mL.toMilligrams(value: 10), "mL without concentration should return nil")
    }

    func test_mL_with_concentration() {
        let result = AmountUnit.mL.toMilligrams(value: 10, concentration: 50)!
        XCTAssertEqual(result, 500, "10 mL * 50 mg/mL = 500 mg")
    }

    func test_tablet_returns_nil() {
        XCTAssertNil(AmountUnit.tablet.toMilligrams(value: 2), "Tablet cannot convert without per-tablet dose info")
    }

    func test_allCases_has_5_units() {
        XCTAssertEqual(AmountUnit.allCases.count, 5)
    }

    func test_displayName_values() {
        XCTAssertEqual(AmountUnit.mg.displayName, "mg")
        XCTAssertEqual(AmountUnit.tablet.displayName, "tablet(s)")
    }
}

// MARK: - SplitMode Tests

final class SplitModeTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(SplitMode.allCases.count, 3)
    }

    func test_displayNames() {
        XCTAssertFalse(SplitMode.equal.displayName.isEmpty)
        XCTAssertFalse(SplitMode.custom.displayName.isEmpty)
        XCTAssertFalse(SplitMode.none.displayName.isEmpty)
    }
}

// MARK: - DoseEventSource Tests

final class DoseEventSourceTests: XCTestCase {

    func test_manual_has_reliable_amount() {
        XCTAssertTrue(DoseEventSource.manual.hasReliableAmount)
    }

    func test_migrated_has_unreliable_amount() {
        XCTAssertFalse(DoseEventSource.migrated.hasReliableAmount)
    }

    func test_allCases_count() {
        XCTAssertEqual(DoseEventSource.allCases.count, 4)
    }

    func test_roundtrip_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source in DoseEventSource.allCases {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(DoseEventSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}

// MARK: - Regimen Tests

final class RegimenTests: XCTestCase {

    func test_isActive_within_range() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 86400)
        let r = Regimen(
            medicationId: "xyrem", startAt: start, endAt: end,
            targetTotalAmountValue: 4500, splitMode: .equal
        )
        XCTAssertTrue(r.isActive(at: Date(timeIntervalSince1970: 43200)))
    }

    func test_isActive_nil_end_means_ongoing() {
        let start = Date(timeIntervalSince1970: 0)
        let r = Regimen(
            medicationId: "xyrem", startAt: start, endAt: nil,
            targetTotalAmountValue: 4500, splitMode: .equal
        )
        XCTAssertTrue(r.isActive(at: Date(timeIntervalSince1970: 999_999_999)))
    }

    func test_isActive_before_start_returns_false() {
        let start = Date(timeIntervalSince1970: 86400)
        let r = Regimen(
            medicationId: "xyrem", startAt: start,
            targetTotalAmountValue: 4500, splitMode: .equal
        )
        XCTAssertFalse(r.isActive(at: Date(timeIntervalSince1970: 0)))
    }

    func test_targetAmountForPart_fiftyFifty() {
        let r = Regimen(
            medicationId: "xyrem", startAt: Date(),
            targetTotalAmountValue: 4500, splitMode: .equal,
            splitPartsRatio: [0.5, 0.5]
        )
        XCTAssertEqual(r.targetAmountForPart(0), 2250)
        XCTAssertEqual(r.targetAmountForPart(1), 2250)
    }

    func test_targetAmountForPart_outOfBounds_returns_zero() {
        let r = Regimen(
            medicationId: "xyrem", startAt: Date(),
            targetTotalAmountValue: 4500, splitMode: .equal,
            splitPartsRatio: [0.5, 0.5]
        )
        XCTAssertEqual(r.targetAmountForPart(5), 0)
        XCTAssertEqual(r.targetAmountForPart(-1), 0)
    }

    func test_hasValidSplitRatio_valid() {
        let r = Regimen(
            medicationId: "xyrem", startAt: Date(),
            targetTotalAmountValue: 4500, splitMode: .custom,
            splitPartsRatio: [0.6, 0.4]
        )
        XCTAssertTrue(r.hasValidSplitRatio)
    }

    func test_hasValidSplitRatio_invalid() {
        let r = Regimen(
            medicationId: "xyrem", startAt: Date(),
            targetTotalAmountValue: 4500, splitMode: .custom,
            splitPartsRatio: [0.5, 0.3]
        )
        XCTAssertFalse(r.hasValidSplitRatio)
    }

    func test_hasValidSplitRatio_none_always_true() {
        let r = Regimen(
            medicationId: "xyrem", startAt: Date(),
            targetTotalAmountValue: 4500, splitMode: .none,
            splitPartsCount: 1, splitPartsRatio: [1.0]
        )
        XCTAssertTrue(r.hasValidSplitRatio)
    }

    func test_isValid_valid_regimen() {
        let r = Regimen.xyremDefault()
        XCTAssertTrue(r.isValid)
    }

    func test_isValid_zero_amount() {
        let r = Regimen(
            medicationId: "x", startAt: Date(),
            targetTotalAmountValue: 0, splitMode: .none,
            splitPartsCount: 1, splitPartsRatio: [1.0]
        )
        XCTAssertFalse(r.isValid)
    }

    func test_isValid_mismatched_parts_count() {
        let r = Regimen(
            medicationId: "x", startAt: Date(),
            targetTotalAmountValue: 100, splitMode: .equal,
            splitPartsCount: 3, splitPartsRatio: [0.5, 0.5]
        )
        XCTAssertFalse(r.isValid)
    }

    func test_isValid_end_before_start() {
        let start = Date(timeIntervalSince1970: 86400)
        let end = Date(timeIntervalSince1970: 0)
        let r = Regimen(
            medicationId: "x", startAt: start, endAt: end,
            targetTotalAmountValue: 100, splitMode: .none,
            splitPartsCount: 1, splitPartsRatio: [1.0]
        )
        XCTAssertFalse(r.isValid)
    }

    // MARK: - Presets

    func test_xyremDefault_4500mg_equal() {
        let r = Regimen.xyremDefault()
        XCTAssertEqual(r.targetTotalAmountValue, 4500)
        XCTAssertEqual(r.splitMode, .equal)
        XCTAssertEqual(r.splitPartsRatio, [0.5, 0.5])
    }

    func test_xyremMax_9000mg() {
        let r = Regimen.xyremMax()
        XCTAssertEqual(r.targetTotalAmountValue, 9000)
    }

    func test_equalSplitRatio_3parts() {
        let ratio = Regimen.equalSplitRatio(parts: 3)
        XCTAssertEqual(ratio.count, 3)
        let sum = ratio.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func test_singleDose_preset() {
        let r = Regimen.singleDose(medicationId: "med1", amountMg: 200)
        XCTAssertEqual(r.splitMode, .none)
        XCTAssertEqual(r.splitPartsCount, 1)
        XCTAssertEqual(r.splitPartsRatio, [1.0])
        XCTAssertTrue(r.isValid)
    }

    func test_biggerEarlier_preset() {
        let r = Regimen.biggerEarlier(medicationId: "med1", totalMg: 4500)
        XCTAssertEqual(r.splitMode, .custom)
        XCTAssertEqual(r.splitPartsRatio, [0.6, 0.4])
        XCTAssertTrue(r.isValid)
    }

    func test_codable_roundtrip() throws {
        let original = Regimen.xyremDefault()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Regimen.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

// MARK: - DoseBundle Tests

final class DoseBundleTests: XCTestCase {

    func test_expectedPartsCount() {
        let b = DoseBundle(
            sessionId: "s1", sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.5, 0.5]
        )
        XCTAssertEqual(b.expectedPartsCount, 2)
    }

    func test_targetAmountForPart() {
        let b = DoseBundle(
            sessionId: "s1", sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.6, 0.4]
        )
        XCTAssertEqual(b.targetAmountForPart(0), 2700)
        XCTAssertEqual(b.targetAmountForPart(1), 1800)
    }

    func test_targetAmountForPart_outOfBounds() {
        let b = DoseBundle(
            sessionId: "s1", sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.5, 0.5]
        )
        XCTAssertEqual(b.targetAmountForPart(99), 0)
    }
}

// MARK: - DoseBundleStatus Tests

final class DoseBundleStatusTests: XCTestCase {

    private func makeBundle(target: Double = 4500, ratio: [Double] = [0.5, 0.5]) -> DoseBundle {
        DoseBundle(
            sessionId: "s1", sessionDate: "2026-01-19",
            targetTotalAmountValue: target,
            targetSplitRatio: ratio
        )
    }

    private func makeEvent(amount: Double?, partIndex: Int? = nil) -> DoseEventWithAmount {
        DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: amount, partIndex: partIndex
        )
    }

    func test_totalAmountTaken() {
        let status = DoseBundleStatus(
            bundle: makeBundle(),
            loggedEvents: [makeEvent(amount: 2250), makeEvent(amount: 2250)]
        )
        XCTAssertEqual(status.totalAmountTaken, 4500)
    }

    func test_onTarget_adherence() {
        let status = DoseBundleStatus(
            bundle: makeBundle(),
            loggedEvents: [makeEvent(amount: 2250), makeEvent(amount: 2250)]
        )
        XCTAssertEqual(status.adherenceStatus, .onTarget)
        XCTAssertTrue(status.isComplete)
        XCTAssertEqual(status.remainingAmount, 0)
    }

    func test_underTarget_adherence() {
        let status = DoseBundleStatus(
            bundle: makeBundle(),
            loggedEvents: [makeEvent(amount: 1000)]
        )
        if case .underTarget = status.adherenceStatus {} else {
            XCTFail("Expected underTarget")
        }
        XCTAssertFalse(status.isComplete)
        XCTAssertEqual(status.remainingAmount, 3500)
    }

    func test_overTarget_adherence() {
        let status = DoseBundleStatus(
            bundle: makeBundle(),
            loggedEvents: [makeEvent(amount: 3000), makeEvent(amount: 3000)]
        )
        if case .overTarget = status.adherenceStatus {} else {
            XCTFail("Expected overTarget")
        }
    }

    func test_nil_amounts_treated_as_zero() {
        let status = DoseBundleStatus(
            bundle: makeBundle(),
            loggedEvents: [makeEvent(amount: nil)]
        )
        XCTAssertEqual(status.totalAmountTaken, 0)
    }
}

// MARK: - DoseEventWithAmount Tests

final class DoseEventWithAmountTests: XCTestCase {

    func test_hasKnownAmount() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2250
        )
        XCTAssertTrue(e.hasKnownAmount)
    }

    func test_hasKnownAmount_nil() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: nil
        )
        XCTAssertFalse(e.hasKnownAmount)
    }

    func test_formattedAmount_whole_number() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2250, amountUnit: .mg
        )
        XCTAssertEqual(e.formattedAmount, "2250 mg")
    }

    func test_formattedAmount_fractional() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2.5, amountUnit: .g
        )
        XCTAssertEqual(e.formattedAmount, "2.5 g")
    }

    func test_formattedAmount_unknown() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: nil
        )
        XCTAssertEqual(e.formattedAmount, "Unknown")
    }

    func test_partLabel() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2250, partIndex: 0, partsCount: 2
        )
        XCTAssertEqual(e.partLabel, "Part 1 of 2")
    }

    func test_partLabel_nil_when_no_index() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2250
        )
        XCTAssertNil(e.partLabel)
    }

    func test_isValid_positive_amount() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 100
        )
        XCTAssertTrue(e.isValid)
    }

    func test_isValid_zero_amount_invalid() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 0
        )
        XCTAssertFalse(e.isValid)
    }

    func test_isValid_negative_amount_invalid() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: -1
        )
        XCTAssertFalse(e.isValid)
    }

    func test_isValid_empty_eventType_invalid() {
        let e = DoseEventWithAmount(
            eventType: "", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 100
        )
        XCTAssertFalse(e.isValid)
    }

    func test_isValid_bad_partIndex_invalid() {
        let e = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 100, partIndex: 5, partsCount: 2
        )
        XCTAssertFalse(e.isValid)
    }

    func test_codable_roundtrip() throws {
        let original = DoseEventWithAmount(
            eventType: "dose1", occurredAt: Date(timeIntervalSince1970: 1000),
            sessionId: "s1", sessionDate: "2026-01-19",
            amountValue: 2250, amountUnit: .mg, source: .manual,
            bundleId: "b1", partIndex: 0, partsCount: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DoseEventWithAmount.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

// MARK: - AdherenceStatus Tests

final class AdherenceStatusTests: XCTestCase {

    func test_onTarget_isOnTarget() {
        XCTAssertTrue(AdherenceStatus.onTarget.isOnTarget)
    }

    func test_underTarget_isNotOnTarget() {
        XCTAssertFalse(AdherenceStatus.underTarget(percentage: 80).isOnTarget)
    }

    func test_displayText_values() {
        XCTAssertEqual(AdherenceStatus.onTarget.displayText, "On Target")
        XCTAssertEqual(AdherenceStatus.unknown.displayText, "Unknown")
        XCTAssertTrue(AdherenceStatus.underTarget(percentage: 80).displayText.contains("Under"))
        XCTAssertTrue(AdherenceStatus.overTarget(percentage: 120).displayText.contains("Over"))
    }
}
