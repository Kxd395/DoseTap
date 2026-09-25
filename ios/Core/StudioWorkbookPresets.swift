import Foundation

extension StudioWorkbookData {
    var workbookSchema: Int { medicationPresetLedger == nil ? 3 : 4 }

    func medicationLedgerSheets() throws -> [WorkbookSheet] {
        guard let ledger = medicationPresetLedger else { return [] }
        func amount(_ value: Decimal) -> WorkbookCell { .text(NSDecimalNumber(decimal: value).stringValue) }
        func components(_ values: [MedicationPresetComponent]) -> WorkbookCell {
            SW.text(values.map { "\(NSDecimalNumber(decimal: $0.strengthMilligrams).stringValue) mg/\($0.form.rawValue) × \(NSDecimalNumber(decimal: $0.unitCount).stringValue)" }.joined(separator: "; "))
        }
        func date(_ value: Date?) -> WorkbookCell {
            guard let value else { return .blank }
            return SW.validDate(value).map(WorkbookCell.date) ?? .text("Outside Excel date range; see Source Fields")
        }
        func release(_ preset: MedicationPresetRevision) -> WorkbookCell {
            switch preset.releaseProfile {
            case .immediateRelease: return .text("Immediate release (IR)")
            case .extendedRelease: return .text("Extended release (XR)")
            case .unknown: return .text("Unknown")
            case .other: return SW.text(preset.releaseDetails)
            }
        }
        let presets = try ledger.presetRevisions.map(MedicationPresetExportSnapshot.decodePreset)
        let administrations = try ledger.administrations.map(MedicationPresetExportSnapshot.decodeAdministration)
        let presetRows = try presets.sorted { $0.recordedAt > $1.recordedAt }.map { preset -> [WorkbookCell] in
            [SW.text(preset.labelName), release(preset), amount(try preset.totalMilligrams),
             components(preset.components), SW.text(preset.instructions), .text(preset.schedule.rawValue),
             date(preset.effectiveFrom), date(preset.effectiveUntil), date(preset.recordedAt), SW.text(preset.ingredient),
             .text(preset.presetID.uuidString), .text(preset.revisionID.uuidString), SW.text(preset.supersedesRevisionID?.uuidString)]
        }
        let actualRows = try administrations.sorted { $0.recordedAt > $1.recordedAt }.map { actual -> [WorkbookCell] in
            let local = actual.utcOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:))
                .map { actual.occurredAt.flatMap(SW.validDate) == nil ? date(actual.occurredAt) : SW.local(actual.occurredAt, timezone: $0) } ?? .blank
            return [SW.text(actual.preset.labelName), release(actual.preset), amount(try actual.totalMilligrams),
                    components(actual.actualComponents), .text(actual.precision.rawValue), date(actual.occurredAt), local,
                    SW.text(actual.timeZoneIdentifier), actual.utcOffsetSeconds.map { .number(Double($0)) } ?? .blank,
                    date(actual.confirmedAt), date(actual.recordedAt), .text(actual.id.uuidString),
                    .text(actual.preset.presetID.uuidString), .text(actual.preset.revisionID.uuidString), .text(actual.source.rawValue)]
        }
        return [
            SW.table("Medication Presets", ["Medication", "Release profile", "Planned amount (mg, exact text)", "Components", "Entered instructions",
                "Schedule", "Effective from (UTC)", "Effective until (UTC)", "Recorded (UTC)", "Ingredient", "Preset ID", "Revision ID", "Supersedes revision ID"], presetRows,
                note: "Patient-entered prescription-label revisions, newest recorded first. Plans are not administrations or clinician verification. Amounts are exact decimal text; sort them as text, not numeric dose comparisons. Full immutable JSON is in Source Fields; no treatment-night assignment."),
            SW.table("Confirmed Medications", ["Medication", "Release profile", "Actual amount (mg, exact text)", "Actual components", "Time precision",
                "Occurred (UTC)", "Occurred (recorded offset)", "Recorded timezone", "Recorded UTC offset (seconds)", "Confirmed (UTC)", "Recorded (UTC)",
                "Administration ID", "Preset ID", "Revision ID", "Source"], actualRows,
                note: "One explicitly confirmed taken administration, newest recorded first, independent of nighttime sessions. Unknown occurrence stays blank; confirmation/recording are not substitute occurrence times. Approximate time is not precise timing evidence. Amounts retain exact decimal text and components; full source JSON remains in Source Fields. These rows do not enter Dose 1/2 spacing summaries.")
        ]
    }
}
