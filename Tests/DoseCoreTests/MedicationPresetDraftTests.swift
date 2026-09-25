import XCTest
@testable import DoseCore

final class MedicationPresetDraftTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func testStrictDecimalInputRejectsPartialAmbiguousAndRoundedValues() throws {
        for text in ["", "0", "-1", "1mg", "1.2.3", "1,2", "NaN", "1e3",
                     "123456789012345678901234567890123456789"] {
            XCTAssertThrowsError(try MedicationPresetDraft.amount(text, separator: "."), text)
        }
        XCTAssertEqual(try MedicationPresetDraft.amount(" 1.125 ", separator: "."), Decimal(string: "1.125"))
        XCTAssertEqual(try MedicationPresetDraft.amount("0,5", separator: ","), Decimal(string: "0.5"))
        XCTAssertThrowsError(try MedicationPresetDraft.amount("1.5", separator: ","))
        XCTAssertEqual(try MedicationPresetDraft.amount("1.12345678901234567890123456789", separator: "."), Decimal(string: "1.12345678901234567890123456789"))
        XCTAssertThrowsError(try MedicationPresetDraft.amount("0." + String(repeating: "0", count: 130) + "1", separator: "."))
    }
    func validDraft() -> MedicationPresetDraft {
        var d = MedicationPresetDraft(effectiveFrom: now)
        d.labelName = "Synthetic label"; d.ingredient = "Synthetic ingredient"
        d.releaseProfile = .extendedRelease; d.schedule = .asNeeded; d.instructions = "Entered instructions"
        d.components[0].form = .capsule; d.components[0].strength = "1.25"; d.components[0].count = "2"
        return d
    }
    func testNewChoicesUnansweredAndExplicitReviewRequired() throws {
        let blank = MedicationPresetDraft(effectiveFrom: now)
        XCTAssertNil(blank.releaseProfile); XCTAssertNil(blank.schedule); XCTAssertNil(blank.components[0].form)
        XCTAssertThrowsError(try blank.revision(recordedAt: now, separator: ".", reviewed: true))
        let d = validDraft()
        XCTAssertThrowsError(try d.revision(recordedAt: now, separator: ".", reviewed: false))
        let p = try d.revision(recordedAt: now, separator: ".", reviewed: true)
        XCTAssertEqual(try p.totalMilligrams, Decimal(string: "2.5"))
        XCTAssertNil(p.supersedesRevisionID)
    }
    func testEditingPreservesExactComponentsAndChainLeafWithEqualTimes() throws {
        let a = try validDraft().revision(recordedAt: now, separator: ".", reviewed: true)
        var edit = MedicationPresetDraft(revising: a, separator: ",")
        XCTAssertEqual(edit.components[0].strength, "1,25")
        edit.labelName = "Revised label"; edit.effectiveFrom = now.addingTimeInterval(3600)
        let b = try edit.revision(recordedAt: now, separator: ",", reviewed: true)
        XCTAssertEqual(b.presetID, a.presetID); XCTAssertEqual(b.supersedesRevisionID, a.revisionID)
        XCTAssertNotEqual(a.revisionID, b.revisionID); XCTAssertEqual(a.components, b.components)
        XCTAssertEqual(MedicationPresetDraft.latest(in: [b, a]), [b])
        XCTAssertEqual(MedicationPresetDraft.latest(in: [a, b]), [b])
        XCTAssertFalse(b.isEffective(at: now))
    }
    func testInvalidDatesAndMissingOtherReleaseAreRejected() throws {
        var d = validDraft(); d.effectiveUntil = now
        XCTAssertThrowsError(try d.revision(recordedAt: now, separator: ".", reviewed: true))
        d.effectiveUntil = nil; d.releaseProfile = .other
        XCTAssertThrowsError(try d.revision(recordedAt: now, separator: ".", reviewed: true))
        d.releaseDetails = "Entered release"; d.components[0].count = "0"
        XCTAssertThrowsError(try d.revision(recordedAt: now, separator: ".", reviewed: true))
    }
}
