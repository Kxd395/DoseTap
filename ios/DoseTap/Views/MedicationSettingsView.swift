//
//  MedicationSettingsView.swift
//  DoseTap
//
//  Settings screen for configuring which medications the user takes
//  and their default doses.
//

import SwiftUI
import DoseCore

struct MedicationSettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    @State private var latestInventorySnapshot: StoredInventorySnapshot?
    @State private var inventoryMedicationName = "XYWAV"
    @State private var inventoryBottlesRemaining = 0
    @State private var inventoryDosesRemaining = 0
    @State private var tracksEstimatedDays = false
    @State private var inventoryEstimatedDaysLeft = 0
    @State private var tracksNextRefillDate = false
    @State private var inventoryNextRefillDate = Date()
    @State private var inventoryNotes = ""
    @State private var inventorySavedMessage: String?
    
    var body: some View {
        List {
            // MARK: - Medication Selection
            Section {
                ForEach(MedicationConfig.types) { med in
                    MedicationToggleRow(
                        medication: med,
                        isEnabled: settings.hasMedication(med.id),
                        onToggle: {
                            settings.toggleMedication(med.id)
                        }
                    )
                }
            } header: {
                Label("My Medications", systemImage: "pills.fill")
            } footer: {
                Text("Select the medications you take. Only selected medications will appear in the medication picker.")
            }
            
            // MARK: - Default Doses
            if settings.hasMedication("adderall_ir") || settings.hasMedication("adderall_xr") {
                Section {
                    // Default dose picker
                    HStack {
                        Label("Default Dose", systemImage: "number")
                        Spacer()
                        Menu {
                            ForEach(settings.adderallDoseOptions, id: \.self) { dose in
                                Button {
                                    settings.defaultAdderallDose = dose
                                } label: {
                                    HStack {
                                        Text("\(dose) mg")
                                        if settings.defaultAdderallDose == dose {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(settings.defaultAdderallDose) mg")
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Default formulation picker (if both IR and XR selected)
                    if settings.hasMedication("adderall_ir") && settings.hasMedication("adderall_xr") {
                        HStack {
                            Label("Default Type", systemImage: "capsule.fill")
                            Spacer()
                            Picker("", selection: $settings.defaultAdderallFormulation) {
                                Text("Immediate Release (IR)").tag("ir")
                                Text("Extended Release (XR)").tag("xr")
                            }
                            .pickerStyle(.menu)
                        }
                    }
                } header: {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("These values will be pre-filled when logging a new medication dose.")
                }
            }

            // MARK: - Supply Tracking
            Section {
                if let latestInventorySnapshot {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Snapshot")
                            .font(.subheadline.bold())
                        Text("\(latestInventorySnapshot.medicationName): \(latestInventorySnapshot.bottlesRemaining) bottle(s), \(latestInventorySnapshot.dosesRemaining) dose(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(latestInventorySnapshot.asOfUTC.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                TextField("Medication", text: $inventoryMedicationName)
                    .textInputAutocapitalization(.characters)

                Stepper(value: $inventoryBottlesRemaining, in: 0...99) {
                    inventoryValueRow(title: "Bottles Remaining", value: "\(inventoryBottlesRemaining)")
                }

                Stepper(value: $inventoryDosesRemaining, in: 0...999) {
                    inventoryValueRow(title: "Doses Remaining", value: "\(inventoryDosesRemaining)")
                }

                Toggle("Track Estimated Days", isOn: $tracksEstimatedDays)

                if tracksEstimatedDays {
                    Stepper(value: $inventoryEstimatedDaysLeft, in: 0...365) {
                        inventoryValueRow(title: "Estimated Days Left", value: "\(inventoryEstimatedDaysLeft)")
                    }
                }

                Toggle("Track Next Refill Date", isOn: $tracksNextRefillDate)

                if tracksNextRefillDate {
                    DatePicker("Next Refill", selection: $inventoryNextRefillDate, displayedComponents: .date)
                }

                TextField("Notes", text: $inventoryNotes)

                Button {
                    saveInventorySnapshot()
                } label: {
                    Label("Save Supply Snapshot", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(!canSaveInventorySnapshot)

                if let inventorySavedMessage {
                    Text(inventorySavedMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Medication Supply", systemImage: "shippingbox.fill")
            } footer: {
                Text("Snapshots are exported to inventory.csv for Studio. Dose logs are not used as inventory counts.")
            }
            
            // MARK: - Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(
                        icon: "clock.fill",
                        iconColor: .blue,
                        title: "Duplicate Guard",
                        description: "You'll be warned if logging the same medication within 5 minutes."
                    )
                    
                    InfoRow(
                        icon: "link",
                        iconColor: .purple,
                        title: "Session Linking",
                        description: "Medications are linked to your sleep session for correlation analysis."
                    )
                    
                    InfoRow(
                        icon: "iphone.and.arrow.forward",
                        iconColor: .green,
                        title: "Export",
                        description: "Medication logs can be exported to CSV from Data Management."
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Label("How It Works", systemImage: "info.circle")
            }
        }
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadInventoryDefaults()
        }
    }

    private var canSaveInventorySnapshot: Bool {
        !inventoryMedicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inventoryValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private func loadInventoryDefaults() {
        if let latest = SessionRepository.shared.latestInventorySnapshot() {
            latestInventorySnapshot = latest
            inventoryMedicationName = latest.medicationName
            inventoryBottlesRemaining = latest.bottlesRemaining
            inventoryDosesRemaining = latest.dosesRemaining
            if let estimatedDaysLeft = latest.estimatedDaysLeft {
                tracksEstimatedDays = true
                inventoryEstimatedDaysLeft = estimatedDaysLeft
            }
            if let nextRefillDate = latest.nextRefillDate {
                tracksNextRefillDate = true
                inventoryNextRefillDate = nextRefillDate
            }
            inventoryNotes = latest.notes ?? ""
            return
        }

        guard let data = UserDefaults.standard.data(forKey: "DoseTapUserConfig"),
              let config = try? JSONDecoder().decode(UserConfig.self, from: data) else {
            return
        }

        inventoryMedicationName = config.medicationProfile.medicationName
    }

    private func saveInventorySnapshot() {
        SessionRepository.shared.saveInventorySnapshot(
            medicationName: inventoryMedicationName,
            bottlesRemaining: inventoryBottlesRemaining,
            dosesRemaining: inventoryDosesRemaining,
            estimatedDaysLeft: tracksEstimatedDays ? inventoryEstimatedDaysLeft : nil,
            nextRefillDate: tracksNextRefillDate ? inventoryNextRefillDate : nil,
            notes: inventoryNotes
        )

        latestInventorySnapshot = SessionRepository.shared.latestInventorySnapshot()
        inventorySavedMessage = "Supply snapshot saved."
    }
}

// MARK: - Medication Toggle Row
struct MedicationToggleRow: View {
    let medication: MedicationType
    let isEnabled: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: medication.formulation == .extendedRelease ? "capsule.fill" : "pill.fill")
                    .font(.title2)
                    .foregroundColor(isEnabled ? .orange : .gray)
                    .frame(width: 32)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(formulationDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Checkmark
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isEnabled ? .green : .gray.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var formulationDescription: String {
        switch medication.formulation {
        case .immediateRelease:
            return "Immediate Release • Doses: \(dosesText)"
        case .extendedRelease:
            return "Extended Release • Doses: \(dosesText)"
        case .liquid:
            return "Liquid • Doses: \(dosesText)"
        }
    }
    
    private var dosesText: String {
        medication.validDoses.map { "\($0)mg" }.joined(separator: ", ")
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct MedicationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MedicationSettingsView()
        }
    }
}
#endif
