import XCTest
@testable import DoseCore

final class MedicationPresetTests: XCTestCase {
    let recorded = Date(timeIntervalSince1970: 1_790_000_000)

    func component(_ strength: Decimal = 10, count: Decimal = 1) throws -> MedicationPresetComponent {
        try MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: strength, unitCount: count)
    }

    func revision(components: [MedicationPresetComponent]? = nil,
                  id: UUID = UUID(), predecessor: UUID? = nil) throws -> MedicationPresetRevision {
        try MedicationPresetRevision(presetID: UUID(), revisionID: id, supersedesRevisionID: predecessor,
            labelName: "Synthetic label", ingredient: "Synthetic ingredient", releaseProfile: .extendedRelease,
            components: components ?? [component()], instructions: "As entered from label", schedule: .scheduled,
            effectiveFrom: recorded, effectiveUntil: nil, recordedAt: recorded)
    }

    func mutateJSON<T: Codable>(_ value: T, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testMultipleStrengthsAndFractionalCountsRemainExact() throws {
        let preset = try revision(components: [component(10), component(5, count: Decimal(string: "0.5")!)])
        XCTAssertEqual(try preset.totalMilligrams, Decimal(string: "12.5"))
        XCTAssertEqual(preset.components.count, 2)
        XCTAssertEqual(preset.source, .patientEnteredLabel)
        XCTAssertEqual(try JSONDecoder().decode(MedicationPresetRevision.self,
            from: JSONEncoder().encode(preset)), preset)
    }

    func testInvalidAmountsAndArithmeticFailRatherThanRound() throws {
        for value: Decimal in [0, -1, .nan] {
            XCTAssertThrowsError(try component(value))
            XCTAssertThrowsError(try component(10, count: value))
        }
        let huge = Decimal.greatestFiniteMagnitude
        XCTAssertThrowsError(try component(huge, count: 100))
        XCTAssertThrowsError(try revision(components: [component(huge), component(huge)]))
        let tiny = Decimal.leastNonzeroMagnitude
        XCTAssertThrowsError(try component(tiny, count: tiny))
        XCTAssertThrowsError(try revision(components: [component(huge), component(1)]))
        let precise = try XCTUnwrap(Decimal(string: "1.12345678901234567890123456789012345678"))
        XCTAssertThrowsError(try component(precise, count: precise))
    }

    func testDecodedInvalidPresetCannotBypassValidation() throws {
        let preset = try revision()
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["schemaVersion"] = 2 }, { $0["labelName"] = "  " },
            { $0["ingredient"] = "" }, { $0["instructions"] = "" },
            { $0["components"] = [] }, { $0["supersedesRevisionID"] = preset.revisionID.uuidString },
            { $0["effectiveUntil"] = $0["effectiveFrom"] },
            { $0["releaseProfile"] = "future_release" }, { $0["source"] = "clinician_verified" },
            { $0["releaseProfile"] = "other" }
        ]
        for change in changes {
            XCTAssertThrowsError(try JSONDecoder().decode(MedicationPresetRevision.self,
                from: mutateJSON(preset, change)))
        }
        XCTAssertThrowsError(try revision(id: preset.revisionID, predecessor: preset.revisionID))
        XCTAssertThrowsError(try revision(components: []))
        let repeated = try component()
        XCTAssertThrowsError(try revision(components: [repeated, repeated]))
        XCTAssertThrowsError(try JSONDecoder().decode(MedicationPresetComponent.self,
            from: mutateJSON(component()) { $0["unitCount"] = -1 }))
    }

    func testReleaseAndPhysicalFormStaySeparate() throws {
        let original = try revision()
        let data = try mutateJSON(original) { $0["releaseProfile"] = "unknown" }
        let unknown = try JSONDecoder().decode(MedicationPresetRevision.self, from: data)
        XCTAssertEqual(unknown.releaseProfile, .unknown)
        XCTAssertEqual(unknown.components.first?.form, .tablet)
        XCTAssertEqual(original.releaseProfile, .extendedRelease)
    }

    func testEffectiveIntervalIsHalfOpenAndNoImplicitCurrentClock() throws {
        let original = try revision()
        let end = recorded.addingTimeInterval(3600)
        let bounded = try MedicationPresetRevision(presetID: original.presetID, revisionID: UUID(),
            supersedesRevisionID: original.revisionID, labelName: original.labelName, ingredient: original.ingredient,
            releaseProfile: .other, releaseDetails: "Entered release description", components: original.components,
            instructions: original.instructions, schedule: .asNeeded, effectiveFrom: recorded,
            effectiveUntil: end, recordedAt: recorded)
        XCTAssertFalse(bounded.isEffective(at: recorded.addingTimeInterval(-1)))
        XCTAssertTrue(bounded.isEffective(at: recorded))
        XCTAssertFalse(bounded.isEffective(at: end))
        XCTAssertFalse(bounded.isEffective(at: Date(timeIntervalSince1970: .nan)))
        XCTAssertThrowsError(try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(),
            supersedesRevisionID: nil, labelName: "Label", ingredient: "Ingredient", releaseProfile: .unknown,
            components: [component()], instructions: "Instructions", schedule: .scheduled,
            effectiveFrom: recorded, effectiveUntil: nil, recordedAt: Date(timeIntervalSince1970: .infinity)))
    }

    func administration(_ preset: MedicationPresetRevision, time: Date? = nil,
                        precision: MedicationOccurrencePrecision = .unknown,
                        zone: String? = nil, offset: Int? = nil) throws -> ConfirmedMedicationAdministration {
        try ConfirmedMedicationAdministration(id: UUID(), preset: preset,
            actualComponents: [component(5, count: Decimal(string: "0.5")!)], occurredAt: time,
            precision: precision, timeZoneIdentifier: zone, utcOffsetSeconds: offset,
            confirmedAt: recorded, recordedAt: recorded.addingTimeInterval(30))
    }

    func testActualSnapshotDoesNotInferAmountFromPlanOrChangeWithRevision() throws {
        let preset = try revision()
        let actual = try administration(preset)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(actual)
        let newPreset = try MedicationPresetRevision(presetID: preset.presetID, revisionID: UUID(),
            supersedesRevisionID: preset.revisionID, labelName: "Changed label", ingredient: preset.ingredient,
            releaseProfile: .immediateRelease, components: [component(20)], instructions: "Changed instructions",
            schedule: .asNeeded, effectiveFrom: recorded, effectiveUntil: nil, recordedAt: recorded)
        XCTAssertEqual(newPreset.supersedesRevisionID, preset.revisionID)
        XCTAssertEqual(try actual.totalMilligrams, Decimal(string: "2.5"))
        XCTAssertEqual(try actual.preset.totalMilligrams, 10)
        XCTAssertEqual(actual.preset.releaseProfile, .extendedRelease)
        XCTAssertEqual(try encoder.encode(actual), before)
        XCTAssertEqual(try JSONDecoder().decode(ConfirmedMedicationAdministration.self, from: before), actual)
        XCTAssertEqual(actual.outcome, .taken)
        XCTAssertEqual(actual.source, .userConfirmedPreset)
    }

    func testUnknownOccurrenceHasNoInventedTimeOrZone() throws {
        let actual = try administration(revision())
        XCTAssertNil(actual.occurredAt)
        XCTAssertNil(actual.timeZoneIdentifier)
        XCTAssertNil(actual.utcOffsetSeconds)
        XCTAssertEqual(actual.precision, .unknown)
        XCTAssertNotEqual(actual.confirmedAt, actual.recordedAt)
        XCTAssertThrowsError(try administration(revision(), time: recorded))
        XCTAssertThrowsError(try administration(revision(), zone: "UTC", offset: 0))
        XCTAssertThrowsError(try administration(revision(), precision: .exact))
    }

    func testKnownOccurrencesValidateWithoutConflatingApproximateAndExact() throws {
        let preset = try revision()
        let approximate = try administration(preset, time: recorded.addingTimeInterval(-300),
            precision: .approximate, zone: "UTC", offset: 0)
        XCTAssertEqual(try JSONDecoder().decode(ConfirmedMedicationAdministration.self,
            from: JSONEncoder().encode(approximate)), approximate)
        XCTAssertThrowsError(try administration(preset, time: recorded.addingTimeInterval(1),
            precision: .exact, zone: "UTC", offset: 0))
        XCTAssertThrowsError(try administration(preset, time: recorded, precision: .exact, zone: "Invalid/Zone", offset: 0))
        XCTAssertThrowsError(try administration(preset, time: recorded, precision: .exact, zone: "UTC", offset: 999999))
        for offset in [-64800, 64800] {
            XCTAssertEqual(try administration(preset, time: recorded, precision: .exact,
                zone: "UTC", offset: offset).utcOffsetSeconds, offset)
        }
        for offset in [-64801, 64801] {
            XCTAssertThrowsError(try administration(preset, time: recorded, precision: .exact, zone: "UTC", offset: offset))
        }
        XCTAssertThrowsError(try administration(preset, time: recorded, precision: .exact, zone: "UTC"))
    }

    func testRepeatedDSTHourRetainsAbsoluteOccurrenceAndOriginalOffset() throws {
        let preset = try revision()
        let iso = ISO8601DateFormatter()
        let first = try XCTUnwrap(iso.date(from: "2025-11-02T05:30:00Z"))
        let second = try XCTUnwrap(iso.date(from: "2025-11-02T06:30:00Z"))
        let a = try administration(preset, time: first, precision: .exact, zone: "America/New_York", offset: -14400)
        let b = try administration(preset, time: second, precision: .exact, zone: "America/New_York", offset: -18000)
        let copy = try JSONDecoder().decode(ConfirmedMedicationAdministration.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(copy, b)
        XCTAssertEqual(try XCTUnwrap(b.occurredAt).timeIntervalSince(XCTUnwrap(a.occurredAt)), 3600)
        XCTAssertEqual(a.utcOffsetSeconds, -14400)
        XCTAssertEqual(copy.utcOffsetSeconds, -18000)
    }

    func testDecodedActualRejectsIncompleteAndUnsupportedRecords() throws {
        let actual = try administration(revision())
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["schemaVersion"] = 2 }, { $0["actualComponents"] = [] },
            { $0["outcome"] = "not_recorded" }, { $0["source"] = "automatic" },
            { $0["recordedAt"] = 0 }, { $0["precision"] = "exact" },
            { $0["occurredAt"] = 0 }
        ]
        for change in changes {
            XCTAssertThrowsError(try JSONDecoder().decode(ConfirmedMedicationAdministration.self,
                from: mutateJSON(actual, change)))
        }
    }

    func testHistoricalDecodePreservesZonesUnknownToReceivingPlatform() throws {
        let actual = try administration(revision(), time: recorded, precision: .exact, zone: "UTC", offset: 0)
        let unfamiliar = "Future/Previously_Valid_Zone"
        XCTAssertThrowsError(try administration(actual.preset, time: recorded, precision: .exact,
            zone: unfamiliar, offset: 0))
        let data = try mutateJSON(actual) { $0["timeZoneIdentifier"] = unfamiliar }
        let restored = try JSONDecoder().decode(ConfirmedMedicationAdministration.self, from: data)
        XCTAssertEqual(restored.timeZoneIdentifier, unfamiliar)
        XCTAssertEqual(restored.occurredAt, actual.occurredAt)
        XCTAssertEqual(restored.utcOffsetSeconds, 0)
        XCTAssertEqual(try JSONDecoder().decode(ConfirmedMedicationAdministration.self,
            from: JSONEncoder().encode(restored)), restored)
        XCTAssertThrowsError(try JSONDecoder().decode(ConfirmedMedicationAdministration.self,
            from: mutateJSON(actual) { $0["timeZoneIdentifier"] = "  " }))
    }

    func testIndependentExportSnapshotPreservesPayloadWithoutNights() throws {
        let preset = try revision(components: [component(Decimal(string: "1.12345678901234567890123456789")!)])
        let actual = try administration(preset)
        let snapshot = try MedicationPresetExportSnapshot(presetRevisions: [MedicationPresetExportSnapshot.encode(preset)],
            administrations: [MedicationPresetExportSnapshot.encode(actual)])
        let copy = try JSONDecoder().decode(MedicationPresetExportSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(copy, snapshot)
        XCTAssertTrue(copy.presetRevisions[0].contains("1.12345678901234567890123456789"))
        XCTAssertNil(try MedicationPresetExportSnapshot.decodeAdministration(copy.administrations[0]).occurredAt)
    }

    func testExportSnapshotRejectsMissingRevisionAndDuplicateIDs() throws {
        let preset = try revision(), actual = try administration(preset)
        let p = try MedicationPresetExportSnapshot.encode(preset), a = try MedicationPresetExportSnapshot.encode(actual)
        XCTAssertThrowsError(try MedicationPresetExportSnapshot(presetRevisions: [], administrations: [a]))
        XCTAssertThrowsError(try MedicationPresetExportSnapshot(presetRevisions: [p, p], administrations: []))
        XCTAssertThrowsError(try MedicationPresetExportSnapshot(presetRevisions: [p], administrations: [a, a]))
        XCTAssertThrowsError(try MedicationPresetExportSnapshot(presetRevisions: ["bad"], administrations: []))
        let snapshot = try MedicationPresetExportSnapshot(presetRevisions: [], administrations: [])
        XCTAssertThrowsError(try JSONDecoder().decode(MedicationPresetExportSnapshot.self,
            from: mutateJSON(snapshot) { $0["schemaVersion"] = 99 }))
    }

    func testExportSnapshotRejectsUnresolvedPredecessor() throws {
        let orphan = try revision(predecessor: UUID())
        XCTAssertThrowsError(try MedicationPresetExportSnapshot(
            presetRevisions: [MedicationPresetExportSnapshot.encode(orphan)], administrations: []))
    }
}
