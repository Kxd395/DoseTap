import DoseCore
import Foundation
import SwiftUI

// MARK: - Card 2: Body + Substances
struct Card2BodySubstances: View {
    @Binding var answers: PreSleepLogAnswers
    let medicationSessionKey: String
    @State private var showMedicationPicker = false
    @State private var showPainEntryEditor = false
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var painEntries: [PreSleepLogAnswers.PainEntry] {
        (answers.painEntries ?? []).sorted { $0.entryKey < $1.entryKey }
    }

    private var medicationEntries: [MedicationEntry] {
        sessionRepo.listMedicationEntries(for: medicationSessionKey)
            .sorted { $0.takenAtUTC > $1.takenAtUTC }
    }

    private var plannedTotalNightlyBinding: Binding<Int> {
        Binding(
            get: { answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg() },
            set: { newValue in
                answers.plannedTotalNightlyMg = normalizedTotalNightlyDoseAmount(newValue)
                synchronizeDosePlan()
            }
        )
    }

    private var plannedSplitRatioBinding: Binding<[Double]> {
        Binding(
            get: { answers.resolvedPlannedDoseSplitRatio },
            set: { newValue in
                answers.plannedDoseSplitRatio = normalizedDoseSplitRatio(
                    newValue,
                    totalMg: answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()
                )
                synchronizeDosePlan()
            }
        )
    }

    private var dosePlanPercentages: [Int] {
        answers.plannedDosePercentages ?? [50, 50]
    }

    private var plannedDose1Amount: Int {
        if let explicit = answers.plannedDose1Mg {
            return explicit
        }
        if let total = answers.resolvedPlannedTotalNightlyMg {
            return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[0]).rounded())
        }
        return defaultNightDoseAmountMg()
    }

    private var plannedDose2Amount: Int {
        if let explicit = answers.plannedDose2Mg {
            return explicit
        }
        if let total = answers.resolvedPlannedTotalNightlyMg {
            return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[1]).rounded())
        }
        return defaultNightDoseAmountMg()
    }

    private var hasOffLabelSingleDose: Bool {
        max(plannedDose1Amount, plannedDose2Amount) > 4500
    }

    private var hasHighNightlyDoseTotal: Bool {
        (answers.plannedTotalNightlyMg ?? answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()) > PreSleepLogView.nightlyDoseWarningThresholdMg
    }

    private var dosePlanSection: some View {
        QuestionSection(title: "Tonight's dose plan", icon: "drop.fill") {
            SubstanceDetailCard(title: "Planned oxybate amounts") {
                SubstanceIntStepperRow(
                    label: "Total nightly plan",
                    unit: "mg",
                    range: 500...PreSleepLogView.maxDoseAmountMg,
                    step: 250,
                    value: plannedTotalNightlyBinding
                )

                VStack(spacing: 8) {
                    DosePlanPreviewRow(
                        label: "Dose 1 plan",
                        amountMg: plannedDose1Amount,
                        percentage: dosePlanPercentages[0]
                    )
                    DosePlanPreviewRow(
                        label: "Dose 2 plan",
                        amountMg: plannedDose2Amount,
                        percentage: dosePlanPercentages[1]
                    )
                }

                PreSleepDoseSplitRatioSelector(splitRatio: plannedSplitRatioBinding)

                if hasOffLabelSingleDose {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("One planned dose is above 4,500 mg. Review carefully before saving.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if hasHighNightlyDoseTotal {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Nightly total is above 9,000 mg. Double-check this plan before saving.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Set the total for the night, then adjust the split percentage. These planned amounts prefill the morning reconciliation flow if you miss a dose tap overnight.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                QuestionSection(title: "Body pain right now?", icon: "figure.arms.open") {
                    OptionGrid(
                        options: PreSleepLogAnswers.PainLevel.allCases,
                        selection: $answers.bodyPain
                    )
                }

                if let pain = answers.bodyPain, pain != .none {
                    QuestionSection(title: "Pain detail by area + side", icon: "mappin.and.ellipse") {
                        VStack(spacing: 10) {
                            if painEntries.isEmpty {
                                Text("Add one entry per area/side. Example: Mid Back (Both) 2/10, Lower Back (Right) 9/10.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 2)
                            } else {
                                ForEach(painEntries, id: \.entryKey) { entry in
                                    HStack(spacing: 10) {
                                        GranularPainEntryRow(entry: entry)
                                        Spacer(minLength: 4)
                                        Button {
                                            editingPainEntry = entry
                                            showPainEntryEditor = true
                                        } label: {
                                            Image(systemName: "pencil")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        Button(role: .destructive) {
                                            removePainEntry(entry)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(10)
                                }
                            }

                            Button {
                                editingPainEntry = nil
                                showPainEntryEditor = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Pain Entry")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                QuestionSection(title: "Caffeine / stimulants today?", icon: "cup.and.saucer.fill") {
                    VStack(spacing: 12) {
                        HStack(alignment: .top) {
                            Text("Select every source you had. Leave blank if none.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if answers.hasCaffeineIntake {
                                Button("Clear") {
                                    clearCaffeineDetails()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }

                        MultiSelectGrid(
                            options: PreSleepLogAnswers.caffeineSourceOptions,
                            selections: Binding(
                                get: { answers.resolvedCaffeineSources },
                                set: { updateCaffeineSources($0) }
                            )
                        )

                        if answers.hasLegacyUnspecifiedCaffeineSources {
                            Text("Older entry saved as multiple sources. Leave it as-is or reselect the exact drinks now.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if answers.hasCaffeineIntake {
                            SubstanceDetailCard(title: caffeineDetailTitle) {
                                SubstanceTimePickerRow(
                                    label: "Last intake time",
                                    value: Binding(
                                        get: { answers.caffeineLastIntakeAt ?? Date() },
                                        set: { answers.caffeineLastIntakeAt = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Last drink size",
                                    unit: "oz",
                                    range: 2...48,
                                    step: 2,
                                    value: Binding(
                                        get: { answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz() },
                                        set: { answers.caffeineLastAmountMg = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Total today",
                                    unit: "oz",
                                    range: max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz(), 2)...96,
                                    step: 4,
                                    value: Binding(
                                        get: { answers.caffeineDailyTotalMg ?? max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz(), defaultCaffeineAmountOz()) },
                                        set: { answers.caffeineDailyTotalMg = $0 }
                                    )
                                )
                                Text("Amounts use beverage ounces, not estimated caffeine milligrams.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                QuestionSection(title: "Alcohol today?", icon: "wineglass.fill") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.AlcoholLevel.allCases,
                            selection: $answers.alcohol
                        )
                        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
                            SubstanceDetailCard(title: "Alcohol Details") {
                                SubstanceTimePickerRow(
                                    label: "Last drink time",
                                    value: Binding(
                                        get: { answers.alcoholLastDrinkAt ?? Date() },
                                        set: { answers.alcoholLastDrinkAt = $0 }
                                    )
                                )
                                SubstanceDoubleStepperRow(
                                    label: "Last amount",
                                    unit: "drinks",
                                    range: 0.5...8,
                                    step: 0.5,
                                    value: Binding(
                                        get: { answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks() },
                                        set: { answers.alcoholLastAmountDrinks = $0 }
                                    )
                                )
                                SubstanceDoubleStepperRow(
                                    label: "Daily total",
                                    unit: "drinks",
                                    range: max(answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks(), 0.5)...20,
                                    step: 0.5,
                                    value: Binding(
                                        get: { answers.alcoholDailyTotalDrinks ?? max(answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks(), defaultAlcoholAmountDrinks()) },
                                        set: { answers.alcoholDailyTotalDrinks = $0 }
                                    )
                                )
                            }
                        }
                    }
                }

                QuestionSection(title: "Medications today?", icon: "pills.fill") {
                    VStack(spacing: 12) {
                        Text("Log alerting meds, sleep meds, or anything else you took so the daytime record matches the night review.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if medicationEntries.isEmpty {
                            Text("No medications logged for this session yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(medicationEntries) { entry in
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.displayName)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(formatMedicationDose(entry)) at \(AppFormatters.shortTime.string(from: entry.takenAtUTC))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                                               !notes.isEmpty {
                                                Text(notes)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Button(role: .destructive) {
                                            sessionRepo.deleteMedicationEntry(id: entry.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(10)
                                }
                            }
                        }

                        Button {
                            showMedicationPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text(medicationEntries.isEmpty ? "Log Medication" : "Add Medication")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                    }
                }

                dosePlanSection
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.bodyPain)
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView()
        }
        .sheet(isPresented: $showPainEntryEditor) {
            GranularPainEntryEditorView(initialEntry: editingPainEntry) { result in
                upsertPainEntries(result.entries, replacingEntryKey: result.replacedEntryKey)
            }
        }
        .onChange(of: answers.bodyPain) { newValue in
            guard newValue == .some(PreSleepLogAnswers.PainLevel.none) else { return }
            answers.painEntries = nil
            answers.painLocations = nil
            answers.painType = nil
        }
        .onChange(of: answers.caffeineLastAmountMg) { _ in
            normalizeCaffeineDetails()
        }
        .onChange(of: answers.caffeineDailyTotalMg) { _ in
            normalizeCaffeineDetails()
        }
        .onChange(of: answers.alcohol) { newValue in
            if (newValue ?? PreSleepLogAnswers.AlcoholLevel.none) == PreSleepLogAnswers.AlcoholLevel.none {
                answers.alcoholLastDrinkAt = nil
                answers.alcoholLastAmountDrinks = nil
                answers.alcoholDailyTotalDrinks = nil
            } else {
                if answers.alcoholLastDrinkAt == nil { answers.alcoholLastDrinkAt = Date() }
                if answers.alcoholLastAmountDrinks == nil { answers.alcoholLastAmountDrinks = defaultAlcoholAmountDrinks() }
                if answers.alcoholDailyTotalDrinks == nil { answers.alcoholDailyTotalDrinks = max(defaultAlcoholAmountDrinks(), answers.alcoholLastAmountDrinks ?? 0) }
                normalizeAlcoholDetails()
            }
        }
        .onChange(of: answers.alcoholLastAmountDrinks) { _ in
            normalizeAlcoholDetails()
        }
        .onChange(of: answers.alcoholDailyTotalDrinks) { _ in
            normalizeAlcoholDetails()
        }
        .onAppear {
            bootstrapLegacyPainEntriesIfNeeded()
            bootstrapSubstanceDetailsIfNeeded()
            bootstrapDosePlanIfNeeded()
        }
    }

    private func upsertPainEntries(_ entries: [PreSleepLogAnswers.PainEntry], replacingEntryKey: String?) {
        var updated = answers.painEntries ?? []
        if let replacingEntryKey {
            updated.removeAll { $0.entryKey == replacingEntryKey }
        }
        for entry in entries {
            if let idx = updated.firstIndex(where: { $0.entryKey == entry.entryKey }) {
                updated[idx] = entry
            } else {
                updated.append(entry)
            }
        }
        applyPainEntries(updated)
    }

    private func removePainEntry(_ entry: PreSleepLogAnswers.PainEntry) {
        let updated = (answers.painEntries ?? []).filter { $0.entryKey != entry.entryKey }
        applyPainEntries(updated)
    }

    private func applyPainEntries(_ entries: [PreSleepLogAnswers.PainEntry]) {
        let normalized = entries.sorted { $0.entryKey < $1.entryKey }
        answers.painEntries = normalized.isEmpty ? nil : normalized

        if normalized.isEmpty {
            answers.painLocations = nil
            answers.painType = nil
            answers.bodyPain = PreSleepLogAnswers.PainLevel.none
            return
        }

        answers.painLocations = Array(Set(normalized.map { legacyLocation(for: $0.area) })).sorted { $0.rawValue < $1.rawValue }
        if let firstSensation = normalized.first?.sensations.first {
            answers.painType = legacyPainType(for: firstSensation)
        }
        let maxIntensity = normalized.map(\.intensity).max() ?? 0
        answers.bodyPain = painLevel(for: maxIntensity)
    }

    private func bootstrapLegacyPainEntriesIfNeeded() {
        guard (answers.painEntries ?? []).isEmpty else { return }
        guard let locations = answers.painLocations, !locations.isEmpty else { return }
        guard let bodyPain = answers.bodyPain, bodyPain != .none else { return }

        let intensity: Int
        switch bodyPain {
        case .none: intensity = 0
        case .mild: intensity = 3
        case .moderate: intensity = 6
        case .severe: intensity = 8
        }
        let sensation = answers.painType.map { legacySensation(for: $0) } ?? .aching
        let restored = locations.map { location in
            PreSleepLogAnswers.PainEntry(
                area: area(for: location),
                side: .na,
                intensity: intensity,
                sensations: [sensation],
                pattern: nil,
                notes: nil
            )
        }
        answers.painEntries = restored
    }

    private func legacyLocation(for area: PreSleepLogAnswers.PainArea) -> PreSleepLogAnswers.PainLocation {
        switch area {
        case .headFace: return .head
        case .neck: return .neck
        case .upperBack, .midBack, .lowerBack: return .back
        case .shoulder: return .shoulders
        case .armElbow, .wristHand: return .joints
        case .chestRibs, .abdomen: return .stomach
        case .hipGlute, .knee, .ankleFoot: return .legs
        case .other: return .other
        }
    }

    private func area(for location: PreSleepLogAnswers.PainLocation) -> PreSleepLogAnswers.PainArea {
        switch location {
        case .head: return .headFace
        case .neck: return .neck
        case .back: return .lowerBack
        case .shoulders: return .shoulder
        case .legs: return .ankleFoot
        case .joints: return .knee
        case .stomach: return .abdomen
        case .other: return .other
        }
    }

    private func legacyPainType(for sensation: PreSleepLogAnswers.PainSensation) -> PreSleepLogAnswers.PainType {
        switch sensation {
        case .aching: return .aching
        case .sharp, .shooting, .stabbing: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping, .tightness: return .cramping
        case .radiating, .pinsNeedles, .numbness, .other: return .aching
        }
    }

    private func legacySensation(for type: PreSleepLogAnswers.PainType) -> PreSleepLogAnswers.PainSensation {
        switch type {
        case .aching: return .aching
        case .sharp: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping: return .cramping
        }
    }

    private func painLevel(for intensity: Int) -> PreSleepLogAnswers.PainLevel {
        switch intensity {
        case ..<1: return .none
        case 1...3: return .mild
        case 4...6: return .moderate
        default: return .severe
        }
    }

    private var caffeineDetailTitle: String {
        guard let sources = answers.caffeineSourceDisplayText, !sources.isEmpty else {
            return "Caffeine / Stimulant Details"
        }
        return "Caffeine / Stimulant Details: \(sources)"
    }

    private func updateCaffeineSources(_ sources: [PreSleepLogAnswers.Stimulants]) {
        let sanitized = PreSleepLogAnswers.sanitizedCaffeineSources(sources)
        answers.caffeineSources = sanitized.isEmpty ? nil : sanitized

        if sanitized.isEmpty {
            clearCaffeineDetails()
            return
        }

        answers.stimulants = PreSleepLogAnswers.caffeineSummary(for: sanitized)
        bootstrapCaffeineDetailsIfNeeded()
    }

    private func clearCaffeineDetails() {
        answers.stimulants = PreSleepLogAnswers.Stimulants.none
        answers.caffeineSources = nil
        answers.caffeineLastIntakeAt = nil
        answers.caffeineLastAmountMg = nil
        answers.caffeineDailyTotalMg = nil
    }

    private func defaultCaffeineAmountOz() -> Int {
        switch answers.caffeineSourceSummary ?? answers.stimulants ?? PreSleepLogAnswers.Stimulants.none {
        case .none: return 0
        case .tea: return 8
        case .soda: return 12
        case .coffee: return 12
        case .energyDrink: return 16
        case .multiple: return 24
        }
    }

    private func defaultAlcoholAmountDrinks() -> Double {
        switch answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none {
        case .none: return 0
        case .one: return 1
        case .twoThree: return 2.5
        case .fourPlus: return 4
        }
    }

    private func normalizeCaffeineDetails() {
        guard answers.hasCaffeineIntake else { return }
        if let amount = answers.caffeineLastAmountMg {
            answers.caffeineLastAmountMg = max(2, amount)
        }
        if let total = answers.caffeineDailyTotalMg {
            answers.caffeineDailyTotalMg = max(2, total)
        }
        if let amount = answers.caffeineLastAmountMg,
           let total = answers.caffeineDailyTotalMg,
           total < amount {
            answers.caffeineDailyTotalMg = amount
        }
    }

    private func bootstrapCaffeineDetailsIfNeeded() {
        if answers.caffeineSources == nil {
            let resolved = answers.resolvedCaffeineSources
            answers.caffeineSources = resolved.isEmpty ? nil : resolved
            if !resolved.isEmpty {
                answers.stimulants = PreSleepLogAnswers.caffeineSummary(for: resolved)
            }
        }

        guard answers.hasCaffeineIntake else { return }
        if answers.caffeineLastIntakeAt == nil { answers.caffeineLastIntakeAt = Date() }
        if answers.caffeineLastAmountMg == nil { answers.caffeineLastAmountMg = defaultCaffeineAmountOz() }
        if answers.caffeineDailyTotalMg == nil { answers.caffeineDailyTotalMg = max(defaultCaffeineAmountOz(), answers.caffeineLastAmountMg ?? 0) }
        normalizeCaffeineDetails()
    }

    private func normalizeAlcoholDetails() {
        guard (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none else { return }
        if let amount = answers.alcoholLastAmountDrinks {
            answers.alcoholLastAmountDrinks = max(0.5, amount)
        }
        if let total = answers.alcoholDailyTotalDrinks {
            answers.alcoholDailyTotalDrinks = max(0.5, total)
        }
        if let amount = answers.alcoholLastAmountDrinks,
           let total = answers.alcoholDailyTotalDrinks,
           total < amount {
            answers.alcoholDailyTotalDrinks = amount
        }
    }

    private func bootstrapSubstanceDetailsIfNeeded() {
        bootstrapCaffeineDetailsIfNeeded()

        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
            if answers.alcoholLastDrinkAt == nil { answers.alcoholLastDrinkAt = Date() }
            if answers.alcoholLastAmountDrinks == nil { answers.alcoholLastAmountDrinks = defaultAlcoholAmountDrinks() }
            if answers.alcoholDailyTotalDrinks == nil { answers.alcoholDailyTotalDrinks = max(defaultAlcoholAmountDrinks(), answers.alcoholLastAmountDrinks ?? 0) }
            normalizeAlcoholDetails()
        }
    }

    private func defaultNightDoseAmountMg() -> Int {
        DoseCore.MedicationConfig.nightMedications.first(where: { $0.id != "lumryz" })?.defaultDoseMg
            ?? DoseCore.MedicationConfig.nightMedications.first?.defaultDoseMg
            ?? 4500
    }

    private func defaultNightDoseTotalMg() -> Int {
        max(500, min(PreSleepLogView.maxDoseAmountMg, defaultNightDoseAmountMg() * 2))
    }

    private func normalizedDoseAmount(_ value: Int) -> Int {
        max(250, min(PreSleepLogView.maxDoseAmountMg, value))
    }

    private func normalizedTotalNightlyDoseAmount(_ value: Int) -> Int {
        let clamped = max(500, min(PreSleepLogView.maxDoseAmountMg, value))
        let step = 250
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    private func normalizedDoseSplitRatio(_ ratio: [Double], totalMg: Int) -> [Double] {
        let sanitized = PreSleepLogAnswers.sanitizedDoseSplitRatio(ratio) ?? PreSleepLogAnswers.defaultDoseSplitRatio
        let minComponent = min(0.5, max(250.0 / Double(max(totalMg, 1)), 0.0))
        let clampedFirst = min(max(sanitized[0], minComponent), 1.0 - minComponent)
        let roundedFirst = (clampedFirst * 100).rounded() / 100
        return [roundedFirst, max(0, 1 - roundedFirst)]
    }

    private func synchronizeDosePlan() {
        let total = normalizedTotalNightlyDoseAmount(answers.plannedTotalNightlyMg ?? answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg())
        let splitRatio = normalizedDoseSplitRatio(
            answers.plannedDoseSplitRatio ?? answers.resolvedPlannedDoseSplitRatio,
            totalMg: total
        )
        let dose1 = normalizedDoseAmount(Int((Double(total) * splitRatio[0]).rounded()))
        let dose2 = normalizedDoseAmount(max(250, total - dose1))

        answers.plannedTotalNightlyMg = total
        answers.plannedDose1Mg = dose1
        answers.plannedDose2Mg = dose2
        answers.plannedDoseSplitRatio = [Double(dose1) / Double(total), Double(dose2) / Double(total)]
    }

    private func bootstrapDosePlanIfNeeded() {
        if answers.plannedTotalNightlyMg == nil {
            answers.plannedTotalNightlyMg = normalizedTotalNightlyDoseAmount(
                answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()
            )
        }
        if answers.plannedDoseSplitRatio == nil {
            answers.plannedDoseSplitRatio = normalizedDoseSplitRatio(
                answers.resolvedPlannedDoseSplitRatio,
                totalMg: answers.plannedTotalNightlyMg ?? defaultNightDoseTotalMg()
            )
        }
        synchronizeDosePlan()
    }

    private func formatMedicationDose(_ entry: MedicationEntry) -> String {
        if let medication = MedicationConfig.type(for: entry.medicationId),
           medication.category == .sodiumOxybate {
            return String(format: "%.2f g", Double(entry.doseMg) / 1000.0)
        }
        return "\(entry.doseMg) mg"
    }
}
