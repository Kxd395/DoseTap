import SwiftUI
import DoseCore

@MainActor
final class MedicationPresetSetupModel: ObservableObject {
    @Published var draft: MedicationPresetDraft
    @Published var reviewed = false
    @Published private(set) var pending: MedicationPresetRevision?
    @Published private(set) var error: String?
    @Published private(set) var saved = false
    let separator: String
    private let clock: () -> Date
    private let persist: (MedicationPresetRevision) throws -> Void

    init(previous: MedicationPresetRevision?, separator: String = Locale.current.decimalSeparator ?? ".",
         clock: @escaping () -> Date = Date.init,
         persist: @escaping (MedicationPresetRevision) throws -> Void) {
        self.separator = separator; self.clock = clock; self.persist = persist
        draft = previous.map { MedicationPresetDraft(revising: $0, separator: separator) }
            ?? MedicationPresetDraft(effectiveFrom: clock())
    }
    var preview: MedicationPresetRevision? {
        try? draft.revision(recordedAt: clock(), separator: separator, reviewed: true)
    }
    func save() {
        guard !saved else { return }
        do {
            if pending == nil {
                pending = try draft.revision(recordedAt: clock(), separator: separator, reviewed: reviewed)
            }
            guard let pending else { return }
            try persist(pending)
            saved = true; error = nil
        } catch let failure as MedicationPresetLedgerError {
            error = failure.localizedDescription + " Retry keeps the same revision. For a newer revision conflict, close this editor and reopen the latest saved revision."
        } catch is MedicationPresetDraftError {
            error = "Complete every required choice and enter positive decimal amounts using ‘\(separator)’. Review the label details and dates before saving."
        } catch is MedicationPresetError {
            error = "Check the label, ingredient, instructions, component amounts and effective dates. End must follow start; totals must be exactly representable."
        } catch {
            self.error = "The preset was not confirmed saved. Your entry is retained here. Retry, or return to editing and review it again."
        }
    }
    func returnToEditing() {
        guard !saved else { return }
        pending = nil; reviewed = false; error = nil
    }
}
