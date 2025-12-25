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
