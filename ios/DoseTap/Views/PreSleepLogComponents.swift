import DoseCore
import Foundation
import SwiftUI

// MARK: - Reusable Components

struct QuestionSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            content
        }
    }
}

struct OptionGrid<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String, T: DisplayTextProvider {
    let options: [T]
    @Binding var selection: T?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(option.displayText)
                        .font(.subheadline)
                        .fontWeight(selection == option ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == option ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(selection == option ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MultiSelectGrid<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String, T: DisplayTextProvider {
    let options: [T]
    @Binding var selections: [T]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if selections.contains(option) {
                            selections.removeAll { $0 == option }
                        } else {
                            selections.append(option)
                        }
                    }
                } label: {
                    Text(option.displayText)
                        .font(.subheadline)
                        .fontWeight(selections.contains(option) ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selections.contains(option) ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(selections.contains(option) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StressSlider: View {
    @Binding var value: Int?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = level
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(level)")
                                .font(.title2.bold())
                            Text(stressLabel(level))
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(value == level ? stressColor(level) : Color(.systemGray5))
                        )
                        .foregroundColor(value == level ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stressLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Low"
        case 2: return "Mild"
        case 3: return "Medium"
        case 4: return "High"
        case 5: return "Very High"
        default: return ""
        }
    }

    private func stressColor(_ level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .mint
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }
}

struct SubstanceDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct SubstanceTimePickerRow: View {
    let label: String
    @Binding var value: Date

    var body: some View {
        DatePicker(
            label,
            selection: $value,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.compact)
    }
}

struct PreSleepDoseSplitRatioSelector: View {
    @Binding var splitRatio: [Double]

    private let presets: [(label: String, ratio: [Double])] = [
        ("50/50", [0.5, 0.5]),
        ("55/45", [0.55, 0.45]),
        ("60/40", [0.6, 0.4]),
        ("40/60", [0.4, 0.6])
    ]

    private var dose1Percentage: Binding<Double> {
        Binding(
            get: { (splitRatio.first ?? 0.5) * 100 },
            set: { newValue in
                let ratio1 = newValue / 100
                splitRatio = [ratio1, max(0, 1 - ratio1)]
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split percentage")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(presets, id: \.label) { preset in
                    Button {
                        splitRatio = preset.ratio
                    } label: {
                        Text(preset.label)
                            .font(.caption.weight(isSelected(preset.ratio) ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(isSelected(preset.ratio) ? Color.blue : Color(.tertiarySystemFill))
                            .foregroundColor(isSelected(preset.ratio) ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Dose 1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(dose1Percentage.wrappedValue.rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                }

                Slider(value: dose1Percentage, in: 30...70, step: 1)
                    .tint(.blue)

                HStack {
                    Text("30%")
                    Spacer()
                    Text("70%")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private func isSelected(_ ratio: [Double]) -> Bool {
        guard ratio.count == splitRatio.count else { return false }
        return zip(ratio, splitRatio).allSatisfy { abs($0 - $1) < 0.01 }
    }
}

struct DosePlanPreviewRow: View {
    let label: String
    let amountMg: Int
    let percentage: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(formattedAmount) mg")
                .fontWeight(.semibold)
            Text("(\(percentage)%)")
                .foregroundColor(.secondary)
        }
    }

    private var formattedAmount: String {
        amountMg.formatted(.number.grouping(.automatic))
    }
}

struct SubstanceIntStepperRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.formatted(.number.grouping(.automatic))) \(unit)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SubstanceDoubleStepperRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double

    private var displayValue: String {
        let roundedToInt = abs(value.rounded() - value) < 0.001
        if roundedToInt {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(displayValue) \(unit)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GranularPainEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    struct SaveResult {
        let entries: [PreSleepLogAnswers.PainEntry]
        let replacedEntryKey: String?
    }

    let initialEntry: PreSleepLogAnswers.PainEntry?
    let onSave: (SaveResult) -> Void

    @State private var selectedAreas: Set<PreSleepLogAnswers.PainArea>
    @State private var side: PreSleepLogAnswers.PainSide
    @State private var intensity: Double
    @State private var sensations: Set<PreSleepLogAnswers.PainSensation>
    @State private var pattern: PreSleepLogAnswers.PainPattern?
    @State private var notes: String

    init(
        initialEntry: PreSleepLogAnswers.PainEntry? = nil,
        onSave: @escaping (SaveResult) -> Void
    ) {
        self.initialEntry = initialEntry
        self.onSave = onSave
        _selectedAreas = State(initialValue: initialEntry.map { [$0.area] } ?? [.midBack])
        _side = State(initialValue: initialEntry?.side ?? .both)
        _intensity = State(initialValue: Double(initialEntry?.intensity ?? 5))
        _sensations = State(initialValue: Set(initialEntry?.sensations ?? [.aching]))
        _pattern = State(initialValue: initialEntry?.pattern)
        _notes = State(initialValue: initialEntry?.notes ?? "")
    }

    private var canSave: Bool {
        !sensations.isEmpty && !selectedAreas.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Areas & Side") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PreSleepLogAnswers.PainArea.allCases, id: \.self) { value in
                            Button {
                                toggleArea(value)
                            } label: {
                                Text(value.displayText)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedAreas.contains(value) ? Color.accentColor : Color(.secondarySystemBackground))
                                    )
                                    .foregroundColor(selectedAreas.contains(value) ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedAreas.count > 1 {
                        Text("\(selectedAreas.count) areas selected. The same intensity, side, sensations, and notes will be saved for each area.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Side", selection: $side) {
                        ForEach(PreSleepLogAnswers.PainSide.allCases, id: \.self) { value in
                            Text(value.displayText).tag(value)
                        }
                    }
                }

                Section("Intensity") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(Int(intensity))/10")
                            .font(.headline)
                        Slider(value: $intensity, in: 0...10, step: 1)
                            .tint(.red)
                    }
                }

                Section("Sensations") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PreSleepLogAnswers.PainSensation.allCases, id: \.self) { value in
                            Button {
                                if sensations.contains(value) {
                                    sensations.remove(value)
                                } else {
                                    sensations.insert(value)
                                }
                            } label: {
                                Text(value.displayText)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(sensations.contains(value) ? Color.accentColor : Color(.secondarySystemBackground))
                                    )
                                    .foregroundColor(sensations.contains(value) ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Pattern (optional)") {
                    Picker("Pattern", selection: $pattern) {
                        Text("Not set").tag(Optional<PreSleepLogAnswers.PainPattern>.none)
                        ForEach(PreSleepLogAnswers.PainPattern.allCases, id: \.self) { value in
                            Text(value.displayText).tag(Optional(value))
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("Add detail", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(initialEntry == nil ? "Add Pain Entry" : "Edit Pain Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let entries = selectedAreas
                            .sorted { $0.rawValue < $1.rawValue }
                            .map { area in
                                PreSleepLogAnswers.PainEntry(
                                    area: area,
                                    side: side,
                                    intensity: Int(intensity),
                                    sensations: Array(sensations).sorted { $0.rawValue < $1.rawValue },
                                    pattern: pattern,
                                    notes: normalizedNotes.isEmpty ? nil : notes
                                )
                            }
                        onSave(
                            SaveResult(
                                entries: entries,
                                replacedEntryKey: initialEntry?.entryKey
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func toggleArea(_ area: PreSleepLogAnswers.PainArea) {
        if selectedAreas.contains(area) {
            if selectedAreas.count > 1 {
                selectedAreas.remove(area)
            }
        } else {
            selectedAreas.insert(area)
        }
    }
}

struct GranularPainEntryRow: View {
    let entry: PreSleepLogAnswers.PainEntry

    private var detailText: String {
        let sensationText = entry.sensations.map(\.displayText).joined(separator: ", ")
        if let pattern = entry.pattern {
            return "\(sensationText) • \(pattern.displayText)"
        }
        return sensationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.area.displayText) (\(entry.side.displayText))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(entry.intensity)/10")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.red)
            }
            Text(detailText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Protocol for display text
protocol DisplayTextProvider {
    var displayText: String { get }
}

extension PreSleepLogAnswers.IntendedSleepTime: DisplayTextProvider {}
extension PreSleepLogAnswers.StressDriver: DisplayTextProvider {}
extension PreSleepLogAnswers.StressProgression: DisplayTextProvider {}
extension PreSleepLogAnswers.PainLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.PainLocation: DisplayTextProvider {}
extension PreSleepLogAnswers.PainType: DisplayTextProvider {}
extension PreSleepLogAnswers.Stimulants: DisplayTextProvider {}
extension PreSleepLogAnswers.AlcoholLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.ExerciseLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.ExerciseType: DisplayTextProvider {}
extension PreSleepLogAnswers.NapDuration: DisplayTextProvider {}
extension PreSleepLogAnswers.LaterReason: DisplayTextProvider {}
extension PreSleepLogAnswers.LateMeal: DisplayTextProvider {}
extension PreSleepLogAnswers.ScreensInBed: DisplayTextProvider {}
extension PreSleepLogAnswers.RoomTemp: DisplayTextProvider {}
extension PreSleepLogAnswers.NoiseLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.SleepAid: DisplayTextProvider {}
