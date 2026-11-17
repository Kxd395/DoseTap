import XCTest
@testable import DoseCore

final class MedicationAdministrationAmendmentTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1_790_000_000)

    func preset() throws -> MedicationPresetRevision {
        try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Test label", ingredient: "Test ingredient", releaseProfile: .immediateRelease,
            components: [MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: 10, unitCount: 1)],
            instructions: "Entered label", schedule: .scheduled, effectiveFrom: time, effectiveUntil: nil, recordedAt: time)
    }
    func report(_ p: MedicationPresetRevision, id: UUID = UUID(), delay: Double = 0,
                amount: Decimal = 10, unknown: Bool = false) throws -> ConfirmedMedicationAdministration {
        try ConfirmedMedicationAdministration(id: id, preset: p,
            actualComponents: [MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: amount, unitCount: 1)],
            occurredAt: unknown ? nil : time, precision: unknown ? .unknown : .approximate,
            timeZoneIdentifier: unknown ? nil : "America/New_York", utcOffsetSeconds: unknown ? nil : -14400,
            confirmedAt: time.addingTimeInterval(delay), recordedAt: time.addingTimeInterval(delay))
    }
    func snapshot(_ original: ConfirmedMedicationAdministration) throws -> MedicationPresetExportSnapshot {
        try MedicationPresetExportSnapshot(presetRevisions: [MedicationPresetExportSnapshot.encode(original.preset)],
            administrations: [MedicationPresetExportSnapshot.encode(original)])
    }
    func amendment(_ original: ConfirmedMedicationAdministration, id: UUID = UUID(), parent: UUID? = nil,
                   replacement: ConfirmedMedicationAdministration? = nil, delay: Double = 10) throws -> MedicationAdministrationAmendment {
        try MedicationAdministrationAmendment(id: id, administrationID: original.id, supersedesAmendmentID: parent,
            action: replacement == nil ? .reversal : .correction, replacement: replacement, reason: "Corrected report",
            confirmedAt: time.addingTimeInterval(delay), recordedAt: time.addingTimeInterval(delay))
    }
    func testUnchangedAndEmptyLedger() throws {
        let original = try report(preset())
        let result = try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: [])
        XCTAssertEqual(result.first?.original, original)
        XCTAssertEqual(result.first?.current, original)
        XCTAssertEqual(result.first?.amendments, [])
        XCTAssertTrue(try MedicationAdministrationAudit.project(snapshot:
            MedicationPresetExportSnapshot(presetRevisions: [], administrations: []), amendments: []).isEmpty)
    }
    func testCorrectionAndReversalPreserveEntireChainWithoutInventingSkippedOutcome() throws {
        let original = try report(preset())
        let revised = try report(original.preset, id: original.id, delay: 10, amount: 5, unknown: true)
        let correction = try amendment(original, replacement: revised)
        let reversal = try amendment(original, parent: correction.id, delay: 20)
        let corrected = try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: [correction])[0]
        XCTAssertEqual(corrected.current, revised)
        XCTAssertNil(corrected.current?.occurredAt)
        XCTAssertEqual(corrected.original, original)
        let withdrawn = try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: [reversal, correction])[0]
        XCTAssertNil(withdrawn.current)
        XCTAssertEqual(withdrawn.original.outcome, .taken)
        XCTAssertEqual(withdrawn.amendments, [correction, reversal])
    }
    func testExactDecimalRoundTripAndEqualTimestampChain() throws {
        let original = try report(preset())
        let amount = try XCTUnwrap(Decimal(string: "1.1234567890123456789012345678901234"))
        let revised = try report(original.preset, id: original.id, delay: 10, amount: amount)
        let first = try amendment(original, replacement: revised)
        let second = try amendment(original, parent: first.id)
        let encoded = try MedicationPresetExportSnapshot.encode(first)
        let decoded = try JSONDecoder().decode(MedicationAdministrationAmendment.self, from: Data(encoded.utf8))
        XCTAssertEqual(decoded, first)
        XCTAssertEqual(try decoded.replacement?.totalMilligrams, amount)
        XCTAssertEqual(try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: [second, decoded])[0].amendments, [first, second])
    }
    func testRejectsDuplicateForkOrphanCycleAndUnknownRoot() throws {
        let original = try report(preset())
        let first = try amendment(original)
        let orphan = try amendment(original, parent: UUID())
        let a = UUID(), b = UUID()
        let cycle = try [amendment(original, id: a, parent: b), amendment(original, id: b, parent: a)]
        let unrelated = try amendment(report(original.preset))
        for changes in [[first, first], [first, try amendment(original)], [orphan], cycle, [unrelated]] {
            XCTAssertThrowsError(try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: changes))
        }
    }
    func testRejectsChildOfReversalBackdatedConfirmationAndUnknownPreset() throws {
        let original = try report(preset(), delay: 5)
        let reversed = try amendment(original)
        let child = try amendment(original, parent: reversed.id, delay: 20)
        let backdated = try amendment(original, delay: 0)
        let changed = try report(preset(), id: original.id, delay: 10)
        for changes in [[reversed, child], [backdated], [try amendment(original, replacement: changed)]] {
            XCTAssertThrowsError(try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: changes))
        }
    }
    func testMultipleRootsSortDeterministicallyAndRejectCrossRootLinks() throws {
        let p = try preset()
        let a = try report(p, delay: 1), b = try report(p, delay: 2)
        let ledger = try MedicationPresetExportSnapshot(presetRevisions: [MedicationPresetExportSnapshot.encode(p)],
            administrations: [MedicationPresetExportSnapshot.encode(b), MedicationPresetExportSnapshot.encode(a)])
        XCTAssertEqual(try MedicationAdministrationAudit.project(snapshot: ledger, amendments: []).map(\.original.id), [a.id, b.id])
        let first = try amendment(a)
        let crossRoot = try amendment(b, parent: first.id, delay: 20)
        XCTAssertThrowsError(try MedicationAdministrationAudit.project(snapshot: ledger, amendments: [first, crossRoot]))
        let collision = try amendment(a, id: b.id)
        XCTAssertThrowsError(try MedicationAdministrationAudit.project(snapshot: ledger, amendments: [collision]))
    }
    func testCorrectedKnownTimePreservesAbsoluteInstantAndOriginalOffset() throws {
        let original = try report(preset(), unknown: true)
        let occurrence = time.addingTimeInterval(-86400)
        let revised = try ConfirmedMedicationAdministration(id: original.id, preset: original.preset,
            actualComponents: original.actualComponents, occurredAt: occurrence, precision: .exact,
            timeZoneIdentifier: "America/New_York", utcOffsetSeconds: -18000,
            confirmedAt: time.addingTimeInterval(10), recordedAt: time.addingTimeInterval(10))
        let change = try amendment(original, replacement: revised)
        let result = try MedicationAdministrationAudit.project(snapshot: snapshot(original), amendments: [change])[0]
        XCTAssertNil(result.original.occurredAt)
        XCTAssertEqual(result.current?.occurredAt, occurrence)
        XCTAssertEqual(result.current?.utcOffsetSeconds, -18000)
        XCTAssertEqual(result.current?.precision, .exact)
    }
    func testDecoderCannotBypassActionIdentityReasonTimeOrVersionValidation() throws {
        let original = try report(preset())
        let valid = try amendment(original)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["schemaVersion"] = 2 }, { $0["reason"] = " \n" }, { $0["action"] = "correction" },
            { $0["source"] = "automatic" }, { $0["recordedAt"] = 0 },
            { $0["id"] = original.id.uuidString }, { $0["supersedesAmendmentID"] = valid.id.uuidString }
        ]
        for change in changes {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
            change(&json)
            XCTAssertThrowsError(try JSONDecoder().decode(MedicationAdministrationAmendment.self,
                from: JSONSerialization.data(withJSONObject: json)))
        }
        XCTAssertThrowsError(try amendment(original, replacement: report(original.preset, delay: 10)))
        XCTAssertThrowsError(try amendment(original, replacement: report(original.preset, id: original.id, delay: 20)))
    }
}
