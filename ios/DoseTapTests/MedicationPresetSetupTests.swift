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
    func testStaleEditorRetainsDraftAndDirectsToLatestRevision() throws {
        let repository = SessionRepository(storage: EventStorage(dbPath: ":memory:"), clock: { self.now })
        let create = MedicationPresetSetupModel(previous: nil, separator: ".", clock: { self.now }, persist: repository.saveMedicationPresetRevision)
        fill(create); create.save()
        let original = try XCTUnwrap(create.pending)
        let stale = MedicationPresetSetupModel(previous: original, separator: ".", clock: { self.now }, persist: repository.saveMedicationPresetRevision)
        let newer = MedicationPresetSetupModel(previous: original, separator: ".", clock: { self.now }, persist: repository.saveMedicationPresetRevision)
        newer.draft.labelName = "Newer label"; newer.reviewed = true; newer.save()
        stale.draft.labelName = "Stale draft"; stale.reviewed = true; stale.save()
        XCTAssertFalse(stale.saved); XCTAssertNotNil(stale.pending)
        XCTAssertEqual(stale.draft.labelName, "Stale draft")
        XCTAssertTrue(stale.error?.contains("reopen the latest") == true)
        let snapshot = try repository.medicationPresetExportSnapshot()
        XCTAssertEqual(snapshot.presetRevisions.count, 2)
        XCTAssertTrue(snapshot.administrations.isEmpty)
        let latest = MedicationPresetDraft.latest(in: try snapshot.presetRevisions.map(MedicationPresetExportSnapshot.decodePreset))
        XCTAssertEqual(latest.first?.labelName, "Newer label")
    }

    func testPresetSetupLeavesActiveDoseSessionUnchanged() throws {
        let storage = EventStorage(dbPath: ":memory:")
        let repository = SessionRepository(storage: storage, clock: { self.now })
        XCTAssertTrue(repository.setDose1Time(now.addingTimeInterval(-3600)).isCommitted)
        let session = repository.activeSessionId, dose = repository.dose1Time
        let create = MedicationPresetSetupModel(previous: nil, separator: ".", clock: { self.now }, persist: repository.saveMedicationPresetRevision)
        fill(create); create.save()
        let original = try XCTUnwrap(create.pending)
        let revise = MedicationPresetSetupModel(previous: original, separator: ".", clock: { self.now }, persist: repository.saveMedicationPresetRevision)
        revise.draft.instructions = "Revised label instructions"; revise.reviewed = true; revise.save()
        XCTAssertTrue(revise.saved)
        XCTAssertEqual(repository.activeSessionId, session); XCTAssertEqual(repository.dose1Time, dose)
        XCTAssertNil(repository.dose2Time)
        let snapshot = try repository.medicationPresetExportSnapshot()
        XCTAssertEqual(snapshot.presetRevisions.count, 2); XCTAssertTrue(snapshot.administrations.isEmpty)
        XCTAssertEqual(try MedicationPresetExportSnapshot.decodePreset(snapshot.presetRevisions.first { try MedicationPresetExportSnapshot.decodePreset($0).revisionID == original.revisionID }!), original)
    }

}
