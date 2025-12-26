//
//  MedicationPickerView.swift
//  DoseTap
//
//  Medication Logger: Log one or more medications before saving
//  Supports all FDA-approved narcolepsy medications
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
}

// MARK: - Medication Picker View (Main Container)
struct MedicationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = SessionRepository.shared
    
    // Current entry being edited
    @State private var selectedMedication: MedicationType?
    @State private var selectedDose: Int = 10
    @State private var takenAt: Date = Date()
    @State private var notes: String = ""
    
    // Pending entries (before save)
    @State private var pendingEntries: [PendingMedicationEntry] = []
    
    // UI state
    @State private var showDuplicateAlert = false
    @State private var duplicateResult: DuplicateGuardResult?
    @State private var pendingEntryToConfirm: PendingMedicationEntry?
    @State private var showSuccessToast = false
    @State private var isLogging = false
    @State private var expandedCategory: MedicationCategory? = nil
    
    let onComplete: (() -> Void)?
    
    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Pending entries list (what you've added)
                    if !pendingEntries.isEmpty {
                        pendingEntriesSection
                    }
                    
                    // Add new entry section
                    addNewEntrySection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                    if let entry = pendingEntryToConfirm {
                        pendingEntries.append(entry)
                        resetCurrentEntry()
                    }
                    pendingEntryToConfirm = nil
                }
            } message: {
                if let result = duplicateResult, let existing = result.existingEntry {
                    Text("You logged \(existing.displayName) \(existing.doseMg)mg \(result.minutesDelta) minute\(result.minutesDelta == 1 ? "" : "s") ago. Add another entry?")
                } else if let entry = pendingEntryToConfirm {
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
                    SuccessToast(message: "\(pendingEntries.count) medication\(pendingEntries.count == 1 ? "" : "s") logged")
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
                
                if selectedMedication != nil {
                    Button {
                        addCurrentEntry()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            
            // Medication categories
            ForEach(MedicationCategory.allCases, id: \.self) { category in
                let medsInCategory = DoseCore.MedicationConfig.types.filter { $0.category == category }
                if !medsInCategory.isEmpty {
                    medicationCategorySection(category: category, medications: medsInCategory)
                }
            }
            
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
                    
                    DatePicker(
                        "Time Taken",
                        selection: $takenAt,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding()
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
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
                                    selectedDose = med.defaultDoseMg
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
                ForEach(doses, id: \.self) { dose in
                    Text(formatDose(dose, medication: medication)).tag(dose)
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
        guard let medication = selectedMedication else { return }
        
        let entry = PendingMedicationEntry(
            medication: medication,
            doseMg: selectedDose,
            takenAt: takenAt,
            notes: notes.isEmpty ? nil : notes
        )
        
        // Check for duplicates in pending list
        let hasPendingDuplicate = pendingEntries.contains {
            $0.medication.id == medication.id &&
            abs($0.takenAt.timeIntervalSince(takenAt)) < 300 // within 5 min
        }
        
        // Check for duplicates in database
        let result = repository.checkDuplicateMedication(
            medicationId: medication.id,
            takenAt: takenAt
        )
        
        if hasPendingDuplicate || result.isDuplicate {
            duplicateResult = result
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
        selectedDose = 10
        notes = ""
        // Keep the same time for convenience when logging multiple
    }
    
    private func saveAllEntries() {
        guard !pendingEntries.isEmpty else { return }
        
        isLogging = true
        
        for entry in pendingEntries {
            _ = repository.logMedicationEntry(
                medicationId: entry.medication.id,
                doseMg: entry.doseMg,
                takenAt: entry.takenAt,
                notes: entry.notes,
                confirmedDuplicate: false  // Already confirmed during add
            )
        }
        
        // Success - show toast and dismiss
        withAnimation {
            showSuccessToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onComplete?()
            dismiss()
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
                
                HStack(spacing: 8) {
                    Text(formatDose(entry.doseMg, medication: entry.medication))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(entry.takenAt, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
