//
//  DoseAmountPicker.swift
//  DoseTap
//
//  Created: January 19, 2026
//  Purpose: UI component for selecting dose amounts
//
//  Xyrem/Xywav range: 2.25g to 9g total nightly dose
//  - Minimum single dose: 2.25g (one dose of 50/50 split at minimum)
//  - Maximum single dose: 4.5g (one dose of 50/50 split at maximum 9g)
//  - Increments: 0.25g (250mg) for fine control
//

import SwiftUI

// MARK: - Dose Amount Configuration

/// Configuration for dose amount selection
public struct DoseAmountConfig: Sendable {
    public let minimumMg: Double
    public let maximumMg: Double
    public let incrementMg: Double
    public let defaultMg: Double
    public let unit: AmountUnit
    
    public init(
        minimumMg: Double = 500,      // 0.5g minimum per dose
        maximumMg: Double = 4500,     // 4.5g maximum per dose (half of 9g)
        incrementMg: Double = 250,    // 0.25g increments
        defaultMg: Double = 2250,     // 2.25g default (half of 4.5g)
        unit: AmountUnit = .mg
    ) {
        self.minimumMg = minimumMg
        self.maximumMg = maximumMg
        self.incrementMg = incrementMg
        self.defaultMg = defaultMg
        self.unit = unit
    }
    
    /// Preset for Xyrem/Xywav dosing
    public static let xyrem = DoseAmountConfig(
        minimumMg: 500,
        maximumMg: 4500,
        incrementMg: 250,
        defaultMg: 2250
    )
    
    /// Available amounts based on min/max/increment
    public var availableAmounts: [Double] {
        stride(from: minimumMg, through: maximumMg, by: incrementMg).map { $0 }
    }
    
    /// Format amount for display (converts mg to g for larger values)
    public func formatAmount(_ mg: Double) -> String {
        if mg >= 1000 {
            let grams = mg / 1000.0
            if grams == grams.rounded() {
                return String(format: "%.0fg", grams)
            } else {
                return String(format: "%.2fg", grams)
            }
        } else {
            return String(format: "%.0f mg", mg)
        }
    }
}

// MARK: - Dose Amount Picker View

/// SwiftUI picker for selecting a dose amount
public struct DoseAmountPicker: View {
    @Binding var selectedAmountMg: Double
    let config: DoseAmountConfig
    let label: String
    let showGramsDisplay: Bool
    
    public init(
        selectedAmountMg: Binding<Double>,
        config: DoseAmountConfig = .xyrem,
        label: String = "Dose Amount",
        showGramsDisplay: Bool = true
    ) {
        self._selectedAmountMg = selectedAmountMg
        self.config = config
        self.label = label
        self.showGramsDisplay = showGramsDisplay
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                if showGramsDisplay {
                    Text(config.formatAmount(selectedAmountMg))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            // Wheel picker for fine control
            Picker("Amount", selection: $selectedAmountMg) {
                ForEach(config.availableAmounts, id: \.self) { amount in
                    Text(config.formatAmount(amount))
                        .tag(amount)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            
            // Quick select buttons for common amounts
            HStack(spacing: 12) {
                QuickAmountButton(amount: 2250, label: "2.25g", selectedAmount: $selectedAmountMg)
                QuickAmountButton(amount: 2500, label: "2.5g", selectedAmount: $selectedAmountMg)
                QuickAmountButton(amount: 3000, label: "3g", selectedAmount: $selectedAmountMg)
                QuickAmountButton(amount: 3500, label: "3.5g", selectedAmount: $selectedAmountMg)
                QuickAmountButton(amount: 4500, label: "4.5g", selectedAmount: $selectedAmountMg)
            }
        }
        .padding()
    }
}

/// Quick select button for common dose amounts
private struct QuickAmountButton: View {
    let amount: Double
    let label: String
    @Binding var selectedAmount: Double
    
    var isSelected: Bool {
        abs(selectedAmount - amount) < 0.01
    }
    
    var body: some View {
        Button(action: {
            selectedAmount = amount
        }) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
    }
}

// MARK: - Total Nightly Dose Picker

/// Picker for selecting total nightly dose with split preview
public struct TotalNightlyDosePicker: View {
    @Binding var totalAmountMg: Double
    @Binding var splitRatio: [Double]
    let config: DoseAmountConfig
    
    public init(
        totalAmountMg: Binding<Double>,
        splitRatio: Binding<[Double]>,
        config: DoseAmountConfig = DoseAmountConfig(
            minimumMg: 2250,    // Minimum total: 2.25g
            maximumMg: 9000,    // Maximum total: 9g
            incrementMg: 250,
            defaultMg: 4500     // Default: 4.5g
        )
    ) {
        self._totalAmountMg = totalAmountMg
        self._splitRatio = splitRatio
        self.config = config
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Total dose selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Nightly Dose")
                    .font(.headline)
                
                HStack {
                    Text(config.formatAmount(totalAmountMg))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Spacer()
                }
                
                Slider(
                    value: $totalAmountMg,
                    in: config.minimumMg...config.maximumMg,
                    step: config.incrementMg
                )
                .accentColor(.blue)
                
                HStack {
                    Text(config.formatAmount(config.minimumMg))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(config.formatAmount(config.maximumMg))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Split preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Split Preview")
                    .font(.headline)
                
                if splitRatio.count >= 2 {
                    HStack(spacing: 16) {
                        SplitDosePreview(
                            label: "Dose 1",
                            amountMg: totalAmountMg * splitRatio[0],
                            percentage: splitRatio[0]
                        )
                        
                        SplitDosePreview(
                            label: "Dose 2",
                            amountMg: totalAmountMg * splitRatio[1],
                            percentage: splitRatio[1]
                        )
                    }
                }
            }
            
            // Split ratio selector
            SplitRatioSelector(splitRatio: $splitRatio)
        }
        .padding()
    }
}

/// Preview of a single dose in a split
private struct SplitDosePreview: View {
    let label: String
    let amountMg: Double
    let percentage: Double
    
    var formattedAmount: String {
        let grams = amountMg / 1000.0
        return String(format: "%.2fg", grams)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(formattedAmount)
                .font(.title3)
                .fontWeight(.semibold)
            Text(String(format: "%.0f%%", percentage * 100))
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Split Ratio Selector

/// Selector for choosing split ratio
public struct SplitRatioSelector: View {
    @Binding var splitRatio: [Double]
    
    let presets: [(name: String, ratio: [Double])] = [
        ("50/50", [0.5, 0.5]),
        ("60/40", [0.6, 0.4]),
        ("40/60", [0.4, 0.6]),
        ("55/45", [0.55, 0.45]),
        ("45/55", [0.45, 0.55])
    ]
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Split Ratio")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.name) { preset in
                        Button(action: {
                            splitRatio = preset.ratio
                        }) {
                            Text(preset.name)
                                .font(.caption)
                                .fontWeight(isSelected(preset.ratio) ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSelected(preset.ratio) ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(isSelected(preset.ratio) ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
    
    private func isSelected(_ ratio: [Double]) -> Bool {
        guard ratio.count == splitRatio.count else { return false }
        return zip(ratio, splitRatio).allSatisfy { abs($0 - $1) < 0.01 }
    }
}

// MARK: - Dose Logging Sheet

/// Sheet for logging a dose with amount
public struct DoseLoggingSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let doseNumber: Int  // 1 or 2
    let targetAmountMg: Double?  // From regimen, if available
    let onSave: (Double) -> Void
    
    @State private var selectedAmountMg: Double
    @State private var useCustomAmount: Bool = false
    
    public init(
        doseNumber: Int,
        targetAmountMg: Double? = nil,
        initialAmountMg: Double = 2250,
        onSave: @escaping (Double) -> Void
    ) {
        self.doseNumber = doseNumber
        self.targetAmountMg = targetAmountMg
        self.onSave = onSave
        self._selectedAmountMg = State(initialValue: targetAmountMg ?? initialAmountMg)
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Target indicator if regimen exists
                if let target = targetAmountMg {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                        Text("Target: \(formatGrams(target))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                // Amount picker
                DoseAmountPicker(
                    selectedAmountMg: $selectedAmountMg,
                    config: .xyrem,
                    label: "Dose \(doseNumber) Amount"
                )
                
                // Deviation warning
                if let target = targetAmountMg {
                    let deviation = abs(selectedAmountMg - target)
                    if deviation > 250 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Different from target by \(formatGrams(deviation))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Save button
                Button(action: {
                    onSave(selectedAmountMg)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Dose \(doseNumber)")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Log Dose \(doseNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatGrams(_ mg: Double) -> String {
        let grams = mg / 1000.0
        return String(format: "%.2fg", grams)
    }
}

// MARK: - Regimen Setup View

/// View for setting up a dosing regimen
public struct RegimenSetupView: View {
    @Environment(\.dismiss) var dismiss
    
    let medicationId: String
    let onSave: (Regimen) -> Void
    
    @State private var totalAmountMg: Double = 4500
    @State private var splitRatio: [Double] = [0.5, 0.5]
    @State private var notes: String = ""
    
    public init(
        medicationId: String = "xyrem",
        onSave: @escaping (Regimen) -> Void
    ) {
        self.medicationId = medicationId
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Medication header
                    HStack {
                        Image(systemName: "pill.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(medicationId.capitalized)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Dosing Regimen")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Total dose picker
                    TotalNightlyDosePicker(
                        totalAmountMg: $totalAmountMg,
                        splitRatio: $splitRatio
                    )
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                        TextField("e.g., Doctor's instructions", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    
                    // Save button
                    Button(action: saveRegimen) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Regimen")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Setup Regimen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveRegimen() {
        let regimen = Regimen(
            medicationId: medicationId,
            startAt: Date(),
            targetTotalAmountValue: totalAmountMg,
            targetTotalAmountUnit: .mg,
            splitMode: splitRatio == [0.5, 0.5] ? .equal : .custom,
            splitPartsCount: splitRatio.count,
            splitPartsRatio: splitRatio,
            notes: notes.isEmpty ? nil : notes
        )
        onSave(regimen)
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
struct DoseAmountPicker_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DoseAmountPicker(
                selectedAmountMg: .constant(2250),
                label: "Dose 1 Amount"
            )
            
            Divider()
            
            TotalNightlyDosePicker(
                totalAmountMg: .constant(4500),
                splitRatio: .constant([0.5, 0.5])
            )
        }
        .padding()
    }
}
#endif
