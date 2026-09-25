import SwiftUI
import DoseCore

private let presetRetention = "Presets and their revisions are stored on this device and included in exports. Night deletion and age cleanup keep them. Clear All Data or removing the app removes the local ledger; exported copies remain separate."

struct MedicationPresetSettingsView: View {
    @ObservedObject private var repository = SessionRepository.shared
    @State private var revisions: [MedicationPresetRevision] = []
    @State private var readError: String?
    @State private var loaded = false
    @State private var request: PresetEditorRequest?
    @State private var receipt: String?
    private struct PresetEditorRequest: Identifiable {
        let id = UUID()
        let previous: MedicationPresetRevision?
    }
    var body: some View {
        List {
            Section {
                Text("Save information from your prescription label. This does not record a medication as taken or change your nighttime dose reminders.")
                Text("Oral tablets and capsules, one ingredient and release profile per preset. Check the label; these entries are not clinician-verified.")
                    .foregroundStyle(.secondary)
            } header: { Text("Medication setup") }
            Section { Text(presetRetention) } header: { Text("Storage and history") }
            if let readError {
                Section {
                    Text(readError).foregroundStyle(.red)
                    Button("Retry loading") { load() }
                }
            } else if loaded {
                Section {
                    Button("Add medication preset") { request = PresetEditorRequest(previous: nil) }
                        .accessibilityIdentifier("preset-add")
                    if revisions.isEmpty { Text("No saved presets yet.").foregroundStyle(.secondary) }
                }
                ForEach(MedicationPresetDraft.latest(in: revisions), id: \.presetID) { value in
                    Section {
                        PresetRevisionDetails(value: value)
                        Button("Revise preset") { request = PresetEditorRequest(previous: value) }
                            .accessibilityIdentifier("preset-revise-\(value.labelName)")
                        NavigationLink("Revision history") {
                            List {
                                ForEach(history(for: value), id: \.revisionID) { revision in
                                    Section { PresetRevisionDetails(value: revision) }
                                }
                            }.navigationTitle("Preset history")
                        }.accessibilityIdentifier("preset-history-\(value.labelName)")
                    } header: { Text("Latest saved revision") }
                }
            } else { ProgressView("Loading presets") }
        }
        .safeAreaInset(edge: .bottom) {
            if let receipt {
                VStack(alignment: .leading, spacing: 8) {
                    Text(receipt).font(.callout)
                    Button("Dismiss confirmation") { self.receipt = nil }
                        .accessibilityIdentifier("preset-receipt-dismiss")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(.regularMaterial)
            }
        }
        .navigationTitle("Saved medication presets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onReceive(repository.sessionDidChange) { _ in load() }
        .sheet(item: $request, onDismiss: { load() }) { request in
            NavigationStack {
                MedicationPresetEditor(previous: request.previous) {
                    receipt = "Preset saved. No medication was logged as taken."
                }
            }
        }
    }
    private func load() {
        do {
            let snapshot = try repository.medicationPresetExportSnapshot()
            revisions = try snapshot.presetRevisions.map(MedicationPresetExportSnapshot.decodePreset)
            readError = nil; loaded = true
        } catch {
            revisions = []; loaded = false
            readError = "The saved presets could not be read completely. Retry before adding or revising a preset."
        }
    }
    private func history(for latest: MedicationPresetRevision) -> [MedicationPresetRevision] {
        let map = Dictionary(uniqueKeysWithValues: revisions.map { ($0.revisionID, $0) })
        var result = [latest], previous = latest.supersedesRevisionID
        while let id = previous, let value = map[id] {
            result.append(value); previous = value.supersedesRevisionID
        }
        return result
    }
}

private struct MedicationPresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MedicationPresetSetupModel
    @FocusState private var editing: Bool
    let onSaved: () -> Void
    init(previous: MedicationPresetRevision?, onSaved: @escaping () -> Void) {
        _model = StateObject(wrappedValue: MedicationPresetSetupModel(previous: previous) {
            try SessionRepository.shared.saveMedicationPresetRevision($0)
        })
        self.onSaved = onSaved
    }
    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Label / brand name", text: $model.draft.labelName)
                        .accessibilityIdentifier("preset-label").focused($editing)
                    TextField("Single ingredient", text: $model.draft.ingredient)
                        .accessibilityIdentifier("preset-ingredient").focused($editing)
                    Picker("Release profile", selection: $model.draft.releaseProfile) {
                        Text("Choose").tag(Optional<MedicationReleaseProfile>.none)
                        Text("Immediate release (IR)").tag(Optional(MedicationReleaseProfile.immediateRelease))
                        Text("Extended release (XR)").tag(Optional(MedicationReleaseProfile.extendedRelease))
                        Text("Other").tag(Optional(MedicationReleaseProfile.other))
                        Text("Unknown").tag(Optional(MedicationReleaseProfile.unknown))
                    }.accessibilityIdentifier("preset-release")
                    if model.draft.releaseProfile == .other {
                        TextField("Release description", text: $model.draft.releaseDetails).focused($editing)
                    }
                    Text("Enter what the label says. Saving setup does not confirm a dose was taken.")
                        .foregroundStyle(.secondary)
                } header: { Text("Prescription label") }
                ForEach($model.draft.components) { $component in
                    Section {
                        Picker("Form", selection: $component.form) {
                            Text("Choose").tag(Optional<MedicationSolidForm>.none)
                            Text("Tablet").tag(Optional(MedicationSolidForm.tablet))
                            Text("Capsule").tag(Optional(MedicationSolidForm.capsule))
                        }.accessibilityIdentifier("preset-form")
                        VStack(alignment: .leading) {
                            Text("Strength per unit (mg)").font(.caption).foregroundStyle(.secondary)
                            TextField("Required", text: $component.strength)
                                .keyboardType(.decimalPad).accessibilityLabel("Strength per unit (mg)")
                                .accessibilityIdentifier("preset-strength").focused($editing)
                        }
                        VStack(alignment: .leading) {
                            Text("Prescribed number of units").font(.caption).foregroundStyle(.secondary)
                            TextField("Required", text: $component.count)
                                .keyboardType(.decimalPad).accessibilityLabel("Prescribed number of units")
                                .accessibilityIdentifier("preset-count").focused($editing)
                        }
                        if model.draft.components.count > 1 {
                            Button("Remove component", role: .destructive) {
                                model.draft.components.removeAll { $0.id == component.id }
                            }
                        }
                    } header: { Text("Component") }
                }
                Section {
                    Button("Add another strength of this medication") { model.draft.components.append(.init()) }
                    Text("Use ‘\(model.separator)’ as the decimal separator, for example 0\(model.separator)5. Enter milligrams and units separately; do not enter a liquid or combine different ingredients.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Prescribed instructions", text: $model.draft.instructions, axis: .vertical)
                        .accessibilityIdentifier("preset-instructions").focused($editing)
                    Picker("Schedule", selection: $model.draft.schedule) {
                        Text("Choose").tag(Optional<MedicationPresetSchedule>.none)
                        Text("Scheduled").tag(Optional(MedicationPresetSchedule.scheduled))
                        Text("As needed, as prescribed").tag(Optional(MedicationPresetSchedule.asNeeded))
                    }.accessibilityIdentifier("preset-schedule")
                    DatePicker("Effective from", selection: $model.draft.effectiveFrom)
                    Toggle("Set an end date", isOn: Binding(get: { model.draft.effectiveUntil != nil }, set: {
                        model.draft.effectiveUntil = $0 ? model.draft.effectiveFrom : nil
                    }))
                    if model.draft.effectiveUntil != nil {
                        DatePicker("Effective until (exclusive)", selection: Binding(get: {
                            model.draft.effectiveUntil ?? model.draft.effectiveFrom
                        }, set: { model.draft.effectiveUntil = $0 }))
                    }
                    Text("Dates describe this label history, not when medication was taken. Review the suggested start date. An end date must be later than the start.")
                        .foregroundStyle(.secondary)
                } header: { Text("Instructions and dates") }
                Section {
                    if let preview = model.preview {
                        PresetRevisionDetails(value: preview, showRecorded: false)
                    } else {
                        Text("Complete the required choices, positive amounts and valid dates to preview the preset.")
                    }
                    Button {
                        model.reviewed.toggle()
                    } label: {
                        Label("I reviewed the label details, amounts and effective dates",
                              systemImage: model.reviewed ? "checkmark.square.fill" : "square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(model.reviewed ? "Reviewed" : "Not reviewed")
                    .accessibilityAddTraits(model.reviewed ? .isSelected : [])
                    .accessibilityIdentifier("preset-reviewed")
                    Text(presetRetention).foregroundStyle(.secondary)
                } header: { Text("Review setup") }
            }.disabled(model.pending != nil)
            Section {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("preset-save-error")
                }
                Button(model.pending == nil ? "Save preset only" : "Retry same preset") { model.save() }
                    .disabled(model.pending == nil && (!model.reviewed || model.preview == nil))
                    .accessibilityIdentifier("preset-save")
                if model.pending != nil {
                    Button("Return to editing") { model.returnToEditing() }
                }
                Text("Drafts are not saved when you close this editor.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(model.draft.predecessor == nil ? "New preset" : "Revise preset")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }.accessibilityIdentifier("preset-keyboard-done")
            }
        }
        .onChange(of: model.draft) { _ in model.reviewed = false }
        .onChange(of: model.saved) { saved in if saved { onSaved(); dismiss() } }
        .interactiveDismissDisabled(model.pending != nil)
    }
}

private struct PresetRevisionDetails: View {
    let value: MedicationPresetRevision
    var showRecorded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.labelName).font(.headline)
            Text("\(value.ingredient) · \(releaseLabel)")
            ForEach(value.components, id: \.id) { component in
                Text("\(decimal(component.strengthMilligrams)) mg per \(component.form.rawValue) × \(decimal(component.unitCount)) units")
                if let amount = try? component.totalMilligrams { Text("Component total: \(decimal(amount)) mg") }
            }
            if let total = try? value.totalMilligrams { Text("Prescribed total: \(decimal(total)) mg") }
            Text(value.instructions)
            Text(value.schedule == .asNeeded ? "As needed, as prescribed" : "Scheduled")
            Text("Effective from: \(value.effectiveFrom.formatted(date: .abbreviated, time: .shortened))")
            if let until = value.effectiveUntil {
                Text("Effective until (exclusive): \(until.formatted(date: .abbreviated, time: .shortened))")
            }
            if showRecorded {
                Text("Recorded: \(value.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
    }
    private func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private var releaseLabel: String {
        switch value.releaseProfile {
        case .immediateRelease: return "Immediate release (IR)"
        case .extendedRelease: return "Extended release (XR)"
        case .other: return value.releaseDetails ?? "Other"
        case .unknown: return "Release unknown"
        }
    }
}
