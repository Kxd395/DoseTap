import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class MedicationPresetSetupTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func fill(_ model: MedicationPresetSetupModel) {
        model.draft.labelName = "Synthetic label"; model.draft.ingredient = "Synthetic ingredient"
        model.draft.releaseProfile = .extendedRelease; model.draft.schedule = .asNeeded
        model.draft.instructions = "Entered label instructions"
        model.draft.components[0].form = .capsule
        model.draft.components[0].strength = "1.125"; model.draft.components[0].count = "2"
        model.reviewed = true
    }
    func testFailureFreezesWholeCommandAndRetryCommitsOnlyOnce() throws {
        let storage = EventStorage(dbPath: ":memory:")
        let repository = SessionRepository(storage: storage, clock: { self.now })
        var attempts: [MedicationPresetRevision] = []
        let model = MedicationPresetSetupModel(previous: nil, separator: ".", clock: { self.now }) {
            attempts.append($0); try repository.saveMedicationPresetRevision($0)
        }
        fill(model)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Synthetic") : nil }
        model.save()
        XCTAssertFalse(model.saved); XCTAssertNotNil(model.error); XCTAssertNotNil(model.pending)
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().presetRevisions.isEmpty)
        storage.medicationFaultInjector = nil
        model.save(); model.save()
        XCTAssertTrue(model.saved); XCTAssertNil(model.error)
        XCTAssertEqual(attempts.count, 2); XCTAssertEqual(attempts[0], attempts[1])
        XCTAssertEqual(try repository.medicationPresetExportSnapshot().presetRevisions.count, 1)
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().administrations.isEmpty)
        XCTAssertNil(repository.activeSessionId); XCTAssertNil(repository.dose1Time)
    }
    func testReturnToEditingRequiresFreshReviewAndNewCommand() throws {
        var attempts: [MedicationPresetRevision] = []
        let model = MedicationPresetSetupModel(previous: nil, separator: ".", clock: { self.now }) {
            attempts.append($0); throw MedicationPresetLedgerError.notCommitted
        }
        fill(model); model.save(); model.returnToEditing()
        XCTAssertNil(model.pending); XCTAssertFalse(model.reviewed)
        model.draft.labelName = "Corrected label"; model.save()
        XCTAssertEqual(attempts.count, 1)
        model.reviewed = true; model.save()
        XCTAssertEqual(attempts.count, 2)
        XCTAssertNotEqual(attempts[0].revisionID, attempts[1].revisionID)
        XCTAssertEqual(attempts[1].labelName, "Corrected label")
    }
    func testOpeningEditingAndPreviewDoNotWrite() {
        var writes = 0
        let model = MedicationPresetSetupModel(previous: nil, separator: ".", clock: { self.now }) { _ in writes += 1 }
        fill(model); XCTAssertNotNil(model.preview)
        XCTAssertEqual(writes, 0)
    }
}
