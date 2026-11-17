//
//  MedicationPickerView.swift
//  DoseTap
//
//  Medication Logger: Log one or more medications before saving
//  Uses the configured medication catalog; amounts are explicitly reported.
//

import SwiftUI
import DoseCore

// MARK: - Pending Medication Entry (before save)

struct PendingMedicationEntry: Identifiable, Equatable {
    let id = UUID()
    let medication: MedicationType
    let doseMg: Int
    let takenAt: Date
    let notes: String?
    var confirmedDuplicate = false
    var reviewedDuplicateTokens: Set<Data> = []
}

// MARK: - Medication Picker View (Main Container)
struct MedicationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = SessionRepository.shared
    
    // Current entry being edited
    @State private var selectedMedication: MedicationType?
    @State private var selectedDose: Int?
    @State private var timeMode: String?
    @State private var earlierTimeReviewed = false
    @State private var reviewedDuplicateTokens: Set<Data> = []
    @State private var takenAt: Date = Date()
    @State private var notes: String = ""
    
    // Pending entries (before save)
    @State private var pendingEntries: [PendingMedicationEntry] = []
    
    // UI state
    @State private var showDuplicateAlert = false
    @State private var duplicateEntries: [MedicationEntry] = []
    @State private var pendingEntryToConfirm: PendingMedicationEntry?
    @State private var showSuccessToast = false
    @State private var isLogging = false
    @State private var saveError: String?
    @State private var savedCount = 0
    @State private var savedEntries: [PendingMedicationEntry] = []
    @ObservedObject private var settings = UserSettingsManager.shared
    @State private var expandedCategory: MedicationCategory? = nil
    
    let onComplete: (() -> Void)?
    
    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let saveError { Text(saveError).foregroundColor(.red).accessibilityIdentifier("medication-save-error") }
                    Text("Record medication you already took. Choose the reported amount and time; Save confirms the reviewed list. This does not change Dose 1 or Dose 2.")
                        .font(.callout).foregroundStyle(.secondary)
                    if !savedEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved this visit: \(savedCount)").font(.headline)
                                .accessibilityIdentifier("medication-saved-count")
                            ForEach(savedEntries) { entry in
                                Text("\(entry.medication.displayName) · \(entry.doseMg) mg · \(entry.takenAt.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    }
                    // Pending entries list (what you've added)
                    if !pendingEntries.isEmpty {
                        pendingEntriesSection
                    }
                    
                    // Add new entry section
                    addNewEntrySection
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if selectedMedication != nil {
                    Button("Add") { addCurrentEntry() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedDose == nil || timeMode == nil || (timeMode == "earlier" && !earlierTimeReviewed))
                        .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .disabled(isLogging)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedCount == 0 ? "Cancel" : "Done") {
                        onComplete?()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAllEntries()
                    }
                    .disabled(pendingEntries.isEmpty || isLogging)
                    .fontWeight(.semibold)
                }
            }
            .alert("Duplicate Entry?", isPresented: $showDuplicateAlert) {
                Button("Cancel", role: .cancel) {
                    pendingEntryToConfirm = nil
                }
                Button("Add Anyway", role: .destructive) {
                    if var entry = pendingEntryToConfirm {
                        entry.confirmedDuplicate = true
                        entry.reviewedDuplicateTokens = reviewedDuplicateTokens
                        if let index = pendingEntries.firstIndex(where: { $0.id == entry.id }) { pendingEntries[index] = entry } else { pendingEntries.append(entry) }
                        resetCurrentEntry()
                    }
                    pendingEntryToConfirm = nil
                }
            } message: {
                if !duplicateEntries.isEmpty {
                    Text(duplicateEntries.map {
                        "\($0.displayName) · \($0.doseMg) mg · \($0.takenAtUTC.formatted(date: .abbreviated, time: .shortened))"
                    }.joined(separator: "\n") + "\nThese records are near the reported time. Record another administration?")                } else if let entry = pendingEntryToConfirm {
                    let matchingPending = pendingEntries.first { $0.medication.id == entry.medication.id }
                    if matchingPending != nil {
                        Text("You already added \(entry.medication.displayName) to this batch. Add another?")
                    } else {
                        Text("Add this medication?")
                    }
                }
            }
            .overlay {
                if showSuccessToast {
                    SuccessToast(message: "\(savedCount) medication\(savedCount == 1 ? "" : "s") logged")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Pending Entries Section
    
    private var pendingEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("To Be Logged")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(pendingEntries.count)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            
            ForEach(pendingEntries) { entry in
                PendingEntryRow(entry: entry) {
                    withAnimation {
                        pendingEntries.removeAll { $0.id == entry.id }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Add New Entry Section
    
    private var addNewEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add Medication")
                    .font(.headline)
                
                Spacer()
                

            }
            
            // Medication categories
            ForEach(MedicationCategory.allCases, id: \.self) { category in
                let medsInCategory = DoseCore.MedicationConfig.types.filter { $0.category == category && settings.hasMedication($0.id) }
                if !medsInCategory.isEmpty {
                    medicationCategorySection(category: category, medications: medsInCategory)
                }
            }
            
            NavigationLink("Choose medications in Settings") { MedicationSettingsView() }
                .font(.subheadline)
            // Dose selection (only show if medication selected)
            if let medication = selectedMedication {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dose")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    doseSelector(for: medication)
                }
                
                // Time picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("When")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Now") { timeMode = "now"; earlierTimeReviewed = false }
                            .buttonStyle(.bordered).tint(timeMode == "now" ? .accentColor : .secondary)
                            .accessibilityIdentifier("medication-time-now")
                        Button("Earlier") { timeMode = "earlier"; earlierTimeReviewed = false; takenAt = Date() }
                            .buttonStyle(.bordered).tint(timeMode == "earlier" ? .accentColor : .secondary)
                            .accessibilityIdentifier("medication-time-earlier")
                    }
                    if timeMode == "now" {
                        Text("Now is captured when you tap Add, then shown for review before Save.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if timeMode == "earlier" {
                        DatePicker("Date and time taken", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: takenAt) { _ in earlierTimeReviewed = false }
                        Toggle("I reviewed the occurrence date and time", isOn: $earlierTimeReviewed)
                    } else {
                        Text("Choose when you took it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                
                // Optional notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                        .padding()
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Medication Category Section
    
    private func medicationCategorySection(category: MedicationCategory, medications: [MedicationType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    if expandedCategory == category {
                        expandedCategory = nil
                    } else {
                        expandedCategory = category
                    }
                }
            } label: {
                HStack {
                    Text(category.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: expandedCategory == category ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if expandedCategory == category || medications.contains(where: { $0.id == selectedMedication?.id }) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(medications) { med in
                        MedicationTypeButton(
                            medication: med,
                            isSelected: selectedMedication?.id == med.id,
                            onSelect: {
                                withAnimation {
                                    selectedMedication = med
                                    selectedDose = nil
                                    timeMode = nil
                                    earlierTimeReviewed = false
                                    expandedCategory = category
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Dose Selector
    
    @ViewBuilder
    private func doseSelector(for medication: MedicationType) -> some View {
        let doses = medication.validDoses
        
        if doses.count <= 6 {
            // Segmented for few options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(doses, id: \.self) { dose in
                        Button {
                            selectedDose = dose
                        } label: {
                            Text(formatDose(dose, medication: medication))
                                .font(.subheadline.weight(selectedDose == dose ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedDose == dose ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                                .foregroundColor(selectedDose == dose ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            // Picker for many options
            Picker("Dose", selection: $selectedDose) {
                Text("Choose reported amount").tag(Int?.none)
                ForEach(doses, id: \.self) { dose in
                    Text(formatDose(dose, medication: medication)).tag(Optional(dose))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
        }
    }
    
    private func formatDose(_ dose: Int, medication: MedicationType) -> String {
        if medication.category == .sodiumOxybate {
            // Show in grams for sodium oxybate
            let grams = Double(dose) / 1000.0
            return String(format: "%.2fg", grams)
        } else {
            return "\(dose) mg"
        }
    }
    
    // MARK: - Actions
    
    private func addCurrentEntry() {
        guard let medication = selectedMedication, let selectedDose, let timeMode,
              timeMode != "earlier" || earlierTimeReviewed else { return }
        let occurrence = timeMode == "now" ? Date() : takenAt
        
        let entry = PendingMedicationEntry(
            medication: medication,
            doseMg: selectedDose,
            takenAt: occurrence,
            notes: notes.isEmpty ? nil : notes
        )
        
        // Check for duplicates in pending list
        let hasPendingDuplicate = pendingEntries.contains {
            $0.medication.id == medication.id &&
            abs($0.takenAt.timeIntervalSince(occurrence)) < Double(MedicationConfig.duplicateGuardMinutes * 60) // within 5 min
        }
        
        do {
            let review = try repository.medicationDuplicateReview(medicationId: medication.id, takenAt: occurrence)
            duplicateEntries = review.entries
            reviewedDuplicateTokens = review.tokens
        } catch {
            saveError = "Existing medication records could not be checked. Your entry is kept; try Add again."
            return
        }
        if hasPendingDuplicate || !reviewedDuplicateTokens.isEmpty {
            pendingEntryToConfirm = entry
            showDuplicateAlert = true
        } else {
            withAnimation {
                pendingEntries.append(entry)
                resetCurrentEntry()
            }
        }
    }
    
    private func resetCurrentEntry() {
        selectedMedication = nil
        selectedDose = nil
        timeMode = nil
        earlierTimeReviewed = false
        takenAt = Date()
        notes = ""
    }
    
    private func saveAllEntries() {
        guard !pendingEntries.isEmpty else { return }
        
        isLogging = true
        saveError = nil
        for entry in pendingEntries {
            do {
                let result = try repository.logMedicationEntry(entryID: entry.id.uuidString, medicationId: entry.medication.id, doseMg: entry.doseMg,
                    takenAt: entry.takenAt, notes: entry.notes, confirmedDuplicate: entry.confirmedDuplicate, reviewedDuplicateTokens: entry.reviewedDuplicateTokens)
                guard !result.isDuplicate else {
                    saveError = "This medication was recorded since you added it. Review the duplicate before saving. Earlier saved entries will not be repeated."
                    let review = try repository.medicationDuplicateReview(medicationId: entry.medication.id, takenAt: entry.takenAt)
                    duplicateEntries = review.entries
                    reviewedDuplicateTokens = review.tokens
                    pendingEntryToConfirm = entry
                    showDuplicateAlert = true
                    isLogging = false
                    return
                }
                pendingEntries.removeAll { $0.id == entry.id }
                savedCount += 1
                savedEntries.append(entry)
            } catch {
                saveError = "\(savedCount) saved; \(pendingEntries.count) not saved. \(error.localizedDescription) Your remaining entries are kept."
                isLogging = false
                return
            }
        }

        isLogging = false
        // Keep a receipt visible until the user finishes.
        withAnimation {
            showSuccessToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSuccessToast = false
        }
    }
}

// MARK: - Pending Entry Row

private struct PendingEntryRow: View {
    let entry: PendingMedicationEntry
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: entry.medication.iconName)
                .font(.title3)
                .foregroundColor(Color(hex: entry.medication.colorHex))
                .frame(width: 32)
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.medication.displayName)
                    .font(.subheadline.bold())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDose(entry.doseMg, medication: entry.medication))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(entry.takenAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("medication-pending-occurrence")
                }
            }
            
            Spacer()
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private func formatDose(_ dose: Int, medication: MedicationType) -> String {
        if medication.category == .sodiumOxybate {
            let grams = Double(dose) / 1000.0
            return String(format: "%.2fg", grams)
        } else {
            return "\(dose)mg"
        }
    }
}

// MARK: - Medication Type Button

private struct MedicationTypeButton: View {
    let medication: MedicationType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: medication.iconName)
                    .font(.caption)
                    .foregroundColor(Color(hex: medication.colorHex))
                
                Text(medication.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Spacer(minLength: 0)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Success Toast

private struct SuccessToast: View {
    let message: String
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .cornerRadius(24)
            .shadow(radius: 8)
            
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - MedicationCategory CaseIterable

extension MedicationCategory: @retroactive CaseIterable {
    public static var allCases: [MedicationCategory] {
        [.stimulant, .wakefulnessAgent, .histamineModulator, .sodiumOxybate]
    }
}

// NOTE: Color.init(hex:) extension is defined in UserSettingsManager.swift

// MARK: - Preview

#if DEBUG
struct MedicationPickerView_Previews: PreviewProvider {
    static var previews: some View {
        MedicationPickerView()
    }
}
#endif
