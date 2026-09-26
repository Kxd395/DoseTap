import SwiftUI
import DoseCore

/// An in-memory review of a reported administration; never changes a night or alarm.
@MainActor
final class MedicationAdministrationCaptureModel: ObservableObject {
    enum TimeChoice: String, CaseIterable { case now, earlier, approximate, unknown }
    let preset: MedicationPresetRevision
    let separator: String
    @Published var counts: [String] { didSet { invalidateReview() } }
    @Published var timeChoice: TimeChoice? { didSet { invalidateReview() } }
    @Published var enteredTime: Date { didSet { invalidateReview() } }
    @Published var reviewed = false
    @Published var duplicateAcknowledged = false
    @Published private(set) var duplicates: [ConfirmedMedicationAdministration] = []
    @Published private(set) var pending: ConfirmedMedicationAdministration?
    @Published private(set) var savedReceipt: ConfirmedMedicationAdministration?
    @Published private(set) var error: String?
    private let clock: () -> Date
    private let timeZone: () -> TimeZone
    private let load: () throws -> [ConfirmedMedicationAdministration]
    private let persist: (ConfirmedMedicationAdministration) throws -> Void

    init(preset: MedicationPresetRevision, separator: String = Locale.current.decimalSeparator ?? ".",
         clock: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current },
         load: (() throws -> [ConfirmedMedicationAdministration])? = nil,
         persist: ((ConfirmedMedicationAdministration) throws -> Void)? = nil) {
        self.preset = preset; self.separator = separator; self.clock = clock; self.timeZone = timeZone
        self.load = load ?? {
            try SessionRepository.shared.medicationPresetExportSnapshot().administrations.map(MedicationPresetExportSnapshot.decodeAdministration)
        }
        self.persist = persist ?? { try SessionRepository.shared.saveConfirmedMedicationAdministration($0) }
        counts = preset.components.map {
            NSDecimalNumber(decimal: $0.unitCount).stringValue.replacingOccurrences(of: ".", with: separator)
        }
        enteredTime = clock()
    }
    var saved: Bool { savedReceipt != nil }
    var previewComponents: [MedicationPresetComponent]? { try? actualComponents() }
    var previewTotal: Decimal? {
        // Reuse the checked domain total without freezing an administration or writing anything.
        guard let components = previewComponents else { return nil }
        return try? ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: components,
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil,
            confirmedAt: preset.recordedAt, recordedAt: preset.recordedAt).totalMilligrams
    }
    private func invalidateReview() {
        reviewed = false; duplicateAcknowledged = false
    }
    private func actualComponents() throws -> [MedicationPresetComponent] {
        guard counts.count == preset.components.count else { throw MedicationPresetDraftError.missingChoice }
        let values = try zip(preset.components, counts).compactMap { component, count -> MedicationPresetComponent? in
            let normalized = count.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
                if scalar.properties.generalCategory == .decimalNumber, let digit = scalar.properties.numericValue {
                    return String(Int(digit))
                }
                return String(scalar)
            }.joined()
            let zeroPattern = "^0+(?:" + NSRegularExpression.escapedPattern(for: separator) + "0+)?$"
            if !separator.isEmpty, normalized.range(of: zeroPattern, options: .regularExpression) != nil { return nil }
            return try MedicationPresetComponent(id: component.id, form: component.form,
                strengthMilligrams: component.strengthMilligrams,
                unitCount: MedicationPresetDraft.amount(count, separator: separator))
        }
        guard !values.isEmpty else { throw MedicationPresetDraftError.invalidDecimal }
        return values
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private func candidates() throws -> [ConfirmedMedicationAdministration] {
        try load().filter { value in
            guard value.id != pending?.id else { return false }
            return value.preset.presetID == preset.presetID ||
                (Self.normalized(value.preset.ingredient) == Self.normalized(preset.ingredient) &&
                 value.preset.releaseProfile == preset.releaseProfile &&
                 (preset.releaseProfile != .other ||
                  Self.normalized(value.preset.releaseDetails ?? "") == Self.normalized(preset.releaseDetails ?? "")))
        }.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    /// All matching history, including unknown times and other dates. This is not a dose limit.
    func refreshDuplicateReview() {
        guard !saved else { return }
        do {
            let latest = try candidates()
            if latest != duplicates { duplicateAcknowledged = false }
            duplicates = latest; error = nil
        } catch {
            duplicates = []; duplicateAcknowledged = false
            self.error = "Saved medication history could not be read completely. Review is unavailable; nothing new was saved."
        }
    }
    func save() {
        guard !saved else { return }
        do {
            if pending == nil {
                guard reviewed else { throw MedicationPresetDraftError.reviewRequired }
                guard let timeChoice else { throw MedicationPresetDraftError.missingChoice }
                let now = clock(), zone = timeZone()
                let occurrence: Date? = timeChoice == .unknown ? nil : (timeChoice == .now ? now : enteredTime)
                pending = try ConfirmedMedicationAdministration(id: UUID(), preset: preset,
                    actualComponents: actualComponents(), occurredAt: occurrence,
                    precision: timeChoice == .unknown ? .unknown : (timeChoice == .approximate ? .approximate : .exact),
                    timeZoneIdentifier: occurrence == nil ? nil : zone.identifier,
                    utcOffsetSeconds: occurrence.map { zone.secondsFromGMT(for: $0) }, confirmedAt: now, recordedAt: now)
            }
            guard let pending else { return }
            // Rescan synchronously on MainActor immediately before the synchronous repository write.
            let latest = try candidates()
            if latest != duplicates { duplicates = latest; duplicateAcknowledged = false }
            guard duplicates.isEmpty || duplicateAcknowledged else {
                error = "Review the matching saved records and acknowledge them before saving. These records do not establish a safe dose or dosing interval."
                return
            }
            try persist(pending)
            savedReceipt = pending; error = nil
        } catch is MedicationPresetDraftError {
            error = "Choose when this was taken, enter nonnegative actual counts (at least one nonzero) using ‘\(separator)’, and review the actual amount before saving."
        } catch is MedicationPresetError {
            error = "Check the actual amounts and time. A known time cannot be in the future; amounts must be exactly representable."
        } catch {
            duplicateAcknowledged = false
            self.error = "The record was not confirmed saved. The confirmed entry is retained for Retry; saved history must be readable before retrying."
        }
    }
    func returnToEditing() {
        guard !saved else { return }
        do {
            if let pending, let stored = try load().first(where: { $0.id == pending.id }) {
                guard stored == pending else { throw MedicationPresetLedgerError.conflict }
                savedReceipt = stored; error = nil; return
            }
            pending = nil; reviewed = false; duplicateAcknowledged = false; error = nil
        } catch {
            self.error = "Saved history could not verify this entry. Keep the confirmed entry and retry before returning to editing."
        }
    }
}
