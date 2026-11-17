import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class MedicationAdministrationCaptureTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func preset(ingredient: String = "Synthetic ingredient", release: MedicationReleaseProfile = .extendedRelease,
                previous: MedicationPresetRevision? = nil) throws -> MedicationPresetRevision {
        try MedicationPresetRevision(presetID: previous?.presetID ?? UUID(), revisionID: UUID(),
            supersedesRevisionID: previous?.revisionID, labelName: "Synthetic label", ingredient: ingredient,
            releaseProfile: release,
            components: [MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: Decimal(string: "1.125")!, unitCount: 2),
                         MedicationPresetComponent(id: UUID(), form: .capsule, strengthMilligrams: 3, unitCount: 1)],
            instructions: "Entered label instructions", schedule: .asNeeded,
            effectiveFrom: now.addingTimeInterval(-100_000), effectiveUntil: now.addingTimeInterval(-50_000), recordedAt: now)
    }
    func actual(_ preset: MedicationPresetRevision, occurredAt: Date? = nil) throws -> ConfirmedMedicationAdministration {
        try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: preset.components,
            occurredAt: occurredAt, precision: occurredAt == nil ? .unknown : .exact,
            timeZoneIdentifier: occurredAt == nil ? nil : "UTC", utcOffsetSeconds: occurredAt == nil ? nil : 0,
            confirmedAt: now, recordedAt: now)
    }
    func model(_ p: MedicationPresetRevision, load: @escaping () throws -> [ConfirmedMedicationAdministration] = { [] },
               persist: @escaping (ConfirmedMedicationAdministration) throws -> Void = { _ in }) -> MedicationAdministrationCaptureModel {
        MedicationAdministrationCaptureModel(preset: p, separator: ".", clock: { self.now },
            timeZone: { TimeZone(identifier: "America/New_York")! }, load: load, persist: persist)
    }
    func fill(_ model: MedicationAdministrationCaptureModel) {
        model.timeChoice = .unknown; model.counts = ["1.5", "0"]; model.reviewed = true
    }
    func testNoImplicitTimeOrReviewAndReadOnlyPreview() throws {
        var writes = 0
        let m = model(try preset(), persist: { _ in writes += 1 })
        XCTAssertNil(m.timeChoice); XCTAssertFalse(m.reviewed)
        XCTAssertEqual(m.previewTotal, Decimal(string: "5.25"))
        m.save(); XCTAssertNil(m.pending); XCTAssertEqual(writes, 0)
        m.timeChoice = .now; m.save(); XCTAssertEqual(writes, 0)
        m.reviewed = true; m.counts[0] = "3"; XCTAssertFalse(m.reviewed)
        m.reviewed = true; m.enteredTime = now.addingTimeInterval(-30); XCTAssertFalse(m.reviewed)
    }
    func testActualAmountOmissionAndHistoricalRevisionRemainExact() throws {
        let p = try preset(), m = model(p)
        fill(m); m.save()
        let saved = try XCTUnwrap(m.savedReceipt)
        XCTAssertEqual(saved.preset, p); XCTAssertFalse(p.isEffective(at: now))
        XCTAssertEqual(saved.actualComponents.count, 1)
        XCTAssertEqual(saved.actualComponents[0].unitCount, Decimal(string: "1.5"))
        XCTAssertEqual(try saved.totalMilligrams, Decimal(string: "1.6875"))
        XCTAssertNil(saved.occurredAt); XCTAssertNil(saved.timeZoneIdentifier); XCTAssertNil(saved.utcOffsetSeconds)
    }
    func testLocaleUnicodeZeroAndInvalidInputs() throws {
        let m = MedicationAdministrationCaptureModel(preset: try preset(), separator: ",", clock: { self.now }, load: { [] }, persist: { _ in })
        m.counts = ["١,٥", "٠,٠"]; XCTAssertEqual(m.previewTotal, Decimal(string: "1.6875"))
        for counts in [["0", "0"], ["-1", "0"], ["1.5", "0"], ["1e2", "0"], ["1,", "0"], [String(repeating: "1", count: 39), "0"]] {
            m.counts = counts; XCTAssertNil(m.previewComponents)
            m.timeChoice = .unknown; m.reviewed = true; m.save(); XCTAssertNil(m.savedReceipt)
        }
    }
    func testExplicitTimeChoicesAndFutureRejection() throws {
        for choice in MedicationAdministrationCaptureModel.TimeChoice.allCases {
            let m = model(try preset()); m.enteredTime = now.addingTimeInterval(-90_000)
            m.timeChoice = choice; m.reviewed = true; m.save()
            let saved = try XCTUnwrap(m.savedReceipt)
            XCTAssertEqual(saved.occurredAt, choice == .unknown ? nil : (choice == .now ? now : m.enteredTime))
            XCTAssertEqual(saved.precision, choice == .unknown ? .unknown : (choice == .approximate ? .approximate : .exact))
            if let occurrence = saved.occurredAt {
                XCTAssertEqual(saved.utcOffsetSeconds, TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: occurrence))
            }
        }
        let m = model(try preset()); m.timeChoice = .earlier; m.enteredTime = now.addingTimeInterval(1)
        m.reviewed = true; m.save(); XCTAssertNil(m.pending); XCTAssertNotNil(m.error)
    }
    func testFullLedgerReviewIncludesUnknownAndCrossMidnightAndRescans() throws {
        let p = try preset(), sameIngredient = try preset(ingredient: "  SYNTHETIC  ingredient ")
        let differentRelease = try preset(release: .immediateRelease)
        let old = try actual(p, occurredAt: now.addingTimeInterval(-90_000))
        let unknown = try actual(sameIngredient), excluded = try actual(differentRelease)
        var ledger = [old, unknown, excluded], writes = 0
        let m = model(p, load: { ledger }, persist: { _ in writes += 1 })
        m.refreshDuplicateReview(); XCTAssertEqual(Set(m.duplicates.map(\.id)), Set([old.id, unknown.id]))
        fill(m); m.save(); XCTAssertEqual(writes, 0); XCTAssertNotNil(m.pending)
        m.duplicateAcknowledged = true
        ledger.append(try actual(p)); m.save()
        XCTAssertFalse(m.duplicateAcknowledged); XCTAssertEqual(writes, 0); XCTAssertEqual(m.duplicates.count, 3)
        m.duplicateAcknowledged = true; m.save(); m.save(); XCTAssertEqual(writes, 1); XCTAssertTrue(m.historyReadable)
    }
    func testFailureRetainsFrozenCommandAndRetryPersistsOnceAfterRestart() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let storage = EventStorage(dbPath: path)
        let repository = SessionRepository(storage: storage, clock: { self.now })
        let p = try preset(); try repository.saveMedicationPresetRevision(p)
        var attempts: [ConfirmedMedicationAdministration] = []
        var clockValue = now
        let m = MedicationAdministrationCaptureModel(preset: p, separator: ".", clock: { clockValue }, load: {
            try repository.medicationPresetExportSnapshot().administrations.map(MedicationPresetExportSnapshot.decodeAdministration)
        }, persist: {
            attempts.append($0); try repository.saveConfirmedMedicationAdministration($0)
        })
        fill(m)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Synthetic") : nil }
        m.save(); let frozen = try XCTUnwrap(m.pending)
        XCTAssertNil(m.savedReceipt); XCTAssertNotNil(m.error)
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().administrations.isEmpty)
        clockValue = now.addingTimeInterval(500); m.counts[0] = "9"; m.timeChoice = .now
        storage.medicationFaultInjector = nil
        m.save(); m.save()
        XCTAssertEqual(m.savedReceipt, frozen); XCTAssertEqual(attempts, [frozen, frozen])
        let snapshot = try SessionRepository(storage: EventStorage(dbPath: path), clock: { self.now }).medicationPresetExportSnapshot()
        XCTAssertEqual(snapshot.administrations.count, 1)
        XCTAssertEqual(try MedicationPresetExportSnapshot.decodeAdministration(snapshot.administrations[0]), frozen)
        XCTAssertNil(repository.activeSessionId); XCTAssertNil(repository.dose1Time)
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
    }
    func testUnknownCommitReplayAndReturnToEditingReadback() throws {
        let p = try preset(); var ledger: [ConfirmedMedicationAdministration] = []
        var failRead = false
        let m = model(p, load: {
            if failRead { throw MedicationPresetLedgerError.unreadable }; return ledger
        }, persist: { ledger = [$0]; throw MedicationPresetLedgerError.notCommitted })
        fill(m); m.save(); XCTAssertNil(m.savedReceipt)
        let frozen = m.pending
        failRead = true; m.returnToEditing(); XCTAssertEqual(m.pending, frozen); XCTAssertNil(m.savedReceipt)
        failRead = false; m.returnToEditing(); XCTAssertEqual(m.savedReceipt, frozen)
    }
    func testUnreadableLedgerBlocksSaveAndEditingRequiresNewReview() throws {
        var failRead = true, writes = 0
        let m = model(try preset(), load: {
            if failRead { throw MedicationPresetLedgerError.unreadable }; return []
        }, persist: { _ in writes += 1; throw MedicationPresetLedgerError.notCommitted })
        fill(m); m.refreshDuplicateReview(); XCTAssertNotNil(m.error)
        XCTAssertFalse(m.historyReadable)
        failRead = false; m.refreshDuplicateReview(); XCTAssertTrue(m.historyReadable)
        failRead = true
        m.save(); XCTAssertFalse(m.historyReadable); XCTAssertTrue(m.duplicates.isEmpty)
        let first = try XCTUnwrap(m.pending); XCTAssertEqual(writes, 0)
        failRead = false; m.returnToEditing(); XCTAssertNil(m.pending); XCTAssertFalse(m.reviewed)
        m.save(); XCTAssertNil(m.pending)
        m.reviewed = true; m.save(); XCTAssertNotEqual(m.pending?.id, first.id); XCTAssertEqual(writes, 1); XCTAssertTrue(m.historyReadable)
    }
}
