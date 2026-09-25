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
}
