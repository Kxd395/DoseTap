//
//  MedicationPickerView.swift
//  DoseTap
//
//  Medication Logger: First-class Adderall IR/XR tracking
//  Designed for quick one-handed logging with duplicate guard
//

import SwiftUI
import DoseCore

// MARK: - Medication Picker View (Main Container)
struct MedicationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = SessionRepository.shared
    
    // Input state
    @State private var selectedMedication: MedicationType?
    @State private var selectedDose: Int = 10
    @State private var takenAt: Date = Date()
    @State private var notes: String = ""
    
    // UI state
    @State private var showDuplicateAlert = false
    @State private var duplicateResult: DuplicateGuardResult?
    @State private var showSuccessToast = false
    @State private var isLogging = false
    
    let onComplete: (() -> Void)?
    
    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Medication type selection
                Section {
                    ForEach(MedicationConfig.types) { med in
                        MedicationTypeRow(
                            medication: med,
                            isSelected: selectedMedication?.id == med.id,
                            onSelect: {
                                selectedMedication = med
                                selectedDose = med.defaultDoseMg
                            }
                        )
                    }
                } header: {
                    Text("Medication")
                }
                
                // Dose selection (only show if medication selected)
                if let medication = selectedMedication {
                    Section {
                        Picker("Dose", selection: $selectedDose) {
                            ForEach(medication.validDoses, id: \.self) { dose in
                                Text("\(dose) mg").tag(dose)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Dose")
                    }
                    
                    // Time picker
                    Section {
                        DatePicker(
                            "Time Taken",
                            selection: $takenAt,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } header: {
                        Text("When")
                    }
                    
                    // Optional notes
                    Section {
                        TextField("Optional notes...", text: $notes, axis: .vertical)
                            .lineLimit(3)
                    } header: {
                        Text("Notes")
                    }
                }
            }
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
                        logMedication()
                    }
                    .disabled(selectedMedication == nil || isLogging)
                    .fontWeight(.semibold)
                }
            }
            .alert("Duplicate Entry?", isPresented: $showDuplicateAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Anyway", role: .destructive) {
                    logMedication(confirmedDuplicate: true)
                }
            } message: {
                if let result = duplicateResult, let existing = result.existingEntry {
                    Text("You logged \(existing.displayName) \(existing.doseMg)mg \(result.minutesDelta) minute\(result.minutesDelta == 1 ? "" : "s") ago. Add another entry?")
                }
            }
            .overlay {
                if showSuccessToast {
                    SuccessToast(message: "Medication logged")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func logMedication(confirmedDuplicate: Bool = false) {
        guard let medication = selectedMedication else { return }
        
        isLogging = true
        
        let result = repository.logMedicationEntry(
            medicationId: medication.id,
            doseMg: selectedDose,
            takenAt: takenAt,
            notes: notes.isEmpty ? nil : notes,
            confirmedDuplicate: confirmedDuplicate
        )
        
        if result.isDuplicate && !confirmedDuplicate {
            // Show duplicate warning
            duplicateResult = result
            showDuplicateAlert = true
            isLogging = false
        } else {
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
}

// MARK: - Medication Type Row

private struct MedicationTypeRow: View {
    let medication: MedicationType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon with color
                Image(systemName: medication.iconName)
                    .font(.title2)
                    .foregroundColor(Color(hex: medication.colorHex))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(medication.formulation == .extendedRelease ? "Extended Release" : "Immediate Release")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)
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

// NOTE: Color.init(hex:) extension is defined in UserSettingsManager.swift

// MARK: - Preview

#if DEBUG
struct MedicationPickerView_Previews: PreviewProvider {
    static var previews: some View {
        MedicationPickerView()
    }
}
#endif
