import SwiftUI
import DoseCore

struct MedicationAdministrationCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MedicationAdministrationCaptureModel
    @FocusState private var editing: Bool
    init(preset: MedicationPresetRevision) {
        _model = StateObject(wrappedValue: MedicationAdministrationCaptureModel(preset: preset))
    }
    var body: some View {
        Form {
            if let receipt = model.savedReceipt {
                Section {
                    Text("Medication record saved.").font(.headline)
                        .accessibilityIdentifier("administration-receipt")
                    MedicationAdministrationDetails(value: receipt)
                    Button("Done") { dismiss() }.accessibilityIdentifier("administration-done")
                }
            } else {
                Section {
                    Text(model.preset.labelName).font(.headline)
                    Text("\(model.preset.ingredient) · \(releaseName(model.preset))")
                    Text("Record what you already took. This does not change your prescription or nighttime reminders.")
                    DisclosureGroup("Selected saved prescription") {
                        PresetRevisionDetails(value: model.preset)
                        Text("Revision: \(model.preset.revisionID.uuidString)").font(.caption)
                    }
                }
                Section("Actual amount taken") {
                    Text("Counts start from the saved plan. Review or change them to what you actually took. Enter 0 to omit a component.")
                    ForEach(Array(model.preset.components.enumerated()), id: \.element.id) { index, component in
                        VStack(alignment: .leading) {
                            Text("\(number(component.strengthMilligrams)) mg per \(component.form.rawValue)")
                            TextField("Actual units taken", text: $model.counts[index])
                                .keyboardType(.decimalPad).focused($editing)
                                .accessibilityLabel("Actual units taken, component \(index + 1), \(number(component.strengthMilligrams)) mg per \(component.form.rawValue)")
                                .accessibilityIdentifier("administration-count-\(index)")
                        }
                    }
                    if let total = model.previewTotal { Text("Actual total: \(number(total)) mg") }
                }.disabled(model.pending != nil)
                Section("When was it taken?") {
                    Picker("Occurrence", selection: $model.timeChoice) {
                        Text("Choose time evidence").tag(Optional<MedicationAdministrationCaptureModel.TimeChoice>.none)
                        Text("Now").tag(Optional(MedicationAdministrationCaptureModel.TimeChoice.now))
                        Text("Earlier — exact time").tag(Optional(MedicationAdministrationCaptureModel.TimeChoice.earlier))
                        Text("Approximate time").tag(Optional(MedicationAdministrationCaptureModel.TimeChoice.approximate))
                        Text("Time unknown").tag(Optional(MedicationAdministrationCaptureModel.TimeChoice.unknown))
                    }.accessibilityIdentifier("administration-time")
                    if model.timeChoice == .earlier || model.timeChoice == .approximate {
                        DatePicker("Occurrence date and time", selection: $model.enteredTime,
                                   displayedComponents: [.date, .hourAndMinute])
                        Text("Entry timezone: \(TimeZone.current.identifier)")
                    }
                    if model.timeChoice == .now { Text("Now is captured when you confirm the record.") }
                    if model.timeChoice == .unknown { Text("Taken is recorded without inventing an occurrence time.") }
                }.disabled(model.pending != nil)
                Section("Prior saved-preset records") {
                    Text("This review does not include entries made with the medication picker. Check those records before confirming. Text matches are possible related records, not verified medication equivalence.")
                    if !model.historyReadable { Text("Saved history is unavailable. Retry loading before confirming.")
                        Button("Retry loading history") { model.refreshDuplicateReview() }
                    } else if model.duplicates.isEmpty { Text("No matching saved-preset records found.") }
                    ForEach(Array(model.duplicates.prefix(3)), id: \.id) { MedicationAdministrationDetails(value: $0) }
                    if model.duplicates.count > 3 {
                        DisclosureGroup("More matching records (\(model.duplicates.count - 3))") {
                            ForEach(Array(model.duplicates.dropFirst(3)), id: \.id) { MedicationAdministrationDetails(value: $0) }
                        }
                    }
                    if !model.duplicates.isEmpty {
                        acknowledgement("I reviewed these records; this is a separate administration.", value: $model.duplicateAcknowledged,
                                        id: "administration-duplicate-reviewed")
                    }
                }
                Section {
                    Text("Records remain locally and in exports. Individual correction, reversal and deletion are not available here yet. Review carefully before confirming. An unsaved draft is retained only while this editor stays open.")
                    if model.pending == nil {
                        acknowledgement("I confirm the displayed actual amount and time evidence.", value: $model.reviewed, id: "administration-reviewed")
                    } else if let pending = model.pending {
                        Text("Confirmed entry retained for retry")
                        MedicationAdministrationDetails(value: pending)
                        Button("Return to editing") { model.returnToEditing() }
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("administration-error") }
                    if !model.duplicates.isEmpty && !model.duplicateAcknowledged {
                        Text("Review and acknowledge the matching saved records above before saving.")
                    }
                    Button(model.pending == nil ? "Confirm taken and save" : "Retry confirmed record") { editing = false; model.save() }
                        .disabled((!model.duplicates.isEmpty && !model.duplicateAcknowledged) ||
                                  (model.pending == nil && (!model.reviewed || model.timeChoice == nil || model.previewComponents == nil)))
                        .accessibilityIdentifier("administration-save")
                }
            }
        }
        .id(model.saved) // Start the shorter receipt at its top after a long, scrolled form.
        .navigationTitle("Log taken")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(model.saved ? "Close" : "Cancel") { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Done") { editing = false }.accessibilityIdentifier("administration-keyboard-done")
            }
        }
        .onAppear { model.refreshDuplicateReview() }
        .interactiveDismissDisabled(model.pending != nil && !model.saved)
    }
    private func acknowledgement(_ label: String, value: Binding<Bool>, id: String) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(alignment: .top) {
                Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square")
                Text(label).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
            .accessibilityValue(value.wrappedValue ? "Reviewed" : "Not reviewed")
    }
}

struct MedicationAdministrationDetails: View {
    let value: ConfirmedMedicationAdministration
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value.preset.labelName) · \(releaseName(value.preset))").font(.headline)
            ForEach(value.actualComponents, id: \.id) { c in
                Text("\(number(c.strengthMilligrams)) mg per \(c.form.rawValue) × \(number(c.unitCount)) taken")
            }
            if let amount = try? value.totalMilligrams { Text("Actual total: \(number(amount)) mg") }
            if let date = value.occurredAt, let offset = value.utcOffsetSeconds {
                Text("\(value.precision == .approximate ? "Taken approximately" : "Taken"): \(originalTime(date, offset: offset))")
                Text("Original zone: \(value.timeZoneIdentifier ?? "Not recorded")").font(.caption)
            } else { Text("Taken · Time unknown") }
            Text("Recorded: \(value.recordedAt.formatted(date: .abbreviated, time: .shortened)) (viewer timezone)").font(.caption)
        }.accessibilityElement(children: .combine)
    }
}
private func number(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
private func releaseName(_ value: MedicationPresetRevision) -> String {
    switch value.releaseProfile {
    case .immediateRelease: return "Immediate release (IR)"
    case .extendedRelease: return "Extended release (XR)"
    case .other: return value.releaseDetails ?? "Other"
    case .unknown: return "Release unknown"
    }
}
private func originalTime(_ date: Date, offset: Int) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: offset)
    formatter.dateFormat = "MMM d, yyyy HH:mm:ss XXXXX"
    return formatter.string(from: date)
}
