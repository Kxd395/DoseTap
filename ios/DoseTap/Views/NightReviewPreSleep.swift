import Foundation
import SwiftUI
import DoseCore

// MARK: - Pre-Sleep Log Card
struct PreSleepLogCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var preSleepLog: StoredPreSleepLog? {
        sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionKey)
    }

    private var medicationEntries: [MedicationEntry] {
        sessionRepo.listMedicationEntries(for: sessionKey).sorted { $0.takenAtUTC < $1.takenAtUTC }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🌙 Pre-Sleep Check")
                    .font(.headline)
                Spacer()
                if let log = preSleepLog {
                    Text(log.completionState == "skipped" ? "Skipped" : "Completed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(log.completionState == "skipped" ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(log.completionState == "skipped" ? .orange : .green)
                        .cornerRadius(8)
                } else {
                    Text("Not recorded")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            if let answers = preSleepLog?.answers, preSleepLog?.completionState != "skipped" {
                VStack(spacing: 8) {
                    if let stress = answers.stressLevel {
                        PreSleepRow(label: "Stress Level", value: "\(formatStressLevel(stress)) (\(stress)/5)", icon: "brain.head.profile")
                    }
                    if !answers.resolvedStressDrivers.isEmpty {
                        PreSleepRow(
                            label: "Stressors",
                            value: answers.resolvedStressDrivers.map(\.displayText).joined(separator: ", "),
                            icon: "exclamationmark.triangle"
                        )
                    }
                    if let progression = answers.stressProgression {
                        PreSleepRow(label: "Stress Trend", value: progression.displayText, icon: "chart.line.uptrend.xyaxis")
                    }
                    if let notes = nonEmpty(answers.stressNotes) {
                        PreSleepRow(label: "Stress Notes", value: notes, icon: "square.and.pencil")
                    }
                    if let intended = answers.intendedSleepTime {
                        PreSleepRow(label: "Sleep In", value: intended.displayText, icon: "moon.fill")
                    }

                    if answers.hasCaffeineIntake, let sources = answers.caffeineSourceDisplayText {
                        PreSleepRow(label: "Caffeine Sources", value: sources, icon: "cup.and.saucer.fill", highlight: true)
                    }
                    if let value = answers.caffeineLastIntakeAt {
                        PreSleepRow(label: "Caffeine Last Time", value: shortTimeFormatter.string(from: value), icon: "clock", highlight: true)
                    }
                    if let value = answers.caffeineLastAmountMg {
                        PreSleepRow(label: "Caffeine Last Amount", value: "\(value) oz", icon: "bolt.fill", highlight: true)
                    }
                    if let value = answers.caffeineDailyTotalMg {
                        PreSleepRow(label: "Caffeine Daily Total", value: "\(value) oz", icon: "sum", highlight: true)
                    }
                    if let alcohol = answers.alcohol, alcohol != .none {
                        PreSleepRow(label: "Alcohol", value: alcohol.displayText, icon: "wineglass.fill", highlight: true)
                    }
                    if let value = answers.alcoholLastDrinkAt {
                        PreSleepRow(label: "Alcohol Last Time", value: shortTimeFormatter.string(from: value), icon: "clock", highlight: true)
                    }
                    if let value = answers.alcoholLastAmountDrinks {
                        PreSleepRow(label: "Alcohol Last Amount", value: formatDrinks(value), icon: "drop.fill", highlight: true)
                    }
                    if let value = answers.alcoholDailyTotalDrinks {
                        PreSleepRow(label: "Alcohol Daily Total", value: formatDrinks(value), icon: "sum", highlight: true)
                    }
                    if let total = answers.resolvedPlannedTotalNightlyMg {
                        PreSleepRow(label: "Night Dose Total", value: "\(total.formatted(.number.grouping(.automatic))) mg", icon: "sum")
                    }
                    if let percentages = answers.plannedDosePercentages, percentages.count == 2 {
                        PreSleepRow(
                            label: "Dose Split",
                            value: "Dose 1 \(plannedDoseValueText(answers.plannedDose1Mg)) (\(percentages[0])%), Dose 2 \(plannedDoseValueText(answers.plannedDose2Mg)) (\(percentages[1])%)",
                            icon: "drop.fill",
                            highlight: max(answers.plannedDose1Mg ?? 0, answers.plannedDose2Mg ?? 0) > 4500
                        )
                    }
                    if let meal = answers.lateMeal, meal != .none {
                        PreSleepRow(label: "Late Meal", value: meal.displayText, icon: "fork.knife", highlight: true)
                    }
                    if let value = answers.lateMealEndedAt {
                        PreSleepRow(label: "Late Meal Ended", value: shortTimeFormatter.string(from: value), icon: "clock", highlight: true)
                    }

                    if let nap = answers.napToday, nap != .none {
                        PreSleepRow(label: "Nap Today", value: nap.displayText, icon: "bed.double.fill")
                    }
                    if let value = answers.napCount {
                        PreSleepRow(label: "Nap Count", value: "\(value)", icon: "number.circle")
                    }
                    if let value = answers.napTotalMinutes {
                        PreSleepRow(label: "Total Nap Time", value: "\(value) min", icon: "timer")
                    }
                    if let value = answers.napLastEndAt {
                        PreSleepRow(label: "Last Nap End", value: shortTimeFormatter.string(from: value), icon: "clock")
                    }
                    if let exercise = answers.exercise {
                        PreSleepRow(label: "Exercise", value: exercise.displayText, icon: "figure.run")
                    }
                    if let value = answers.exerciseType {
                        PreSleepRow(label: "Exercise Type", value: value.displayText, icon: "figure.walk")
                    }
                    if let value = answers.exerciseDurationMinutes {
                        PreSleepRow(label: "Exercise Duration", value: "\(value) min", icon: "stopwatch")
                    }
                    if let value = answers.exerciseLastAt {
                        PreSleepRow(label: "Last Exercise Time", value: shortTimeFormatter.string(from: value), icon: "clock")
                    }
                    if let screens = answers.screensInBed, screens != .none {
                        PreSleepRow(label: "Screen Time", value: screens.displayText, icon: "iphone", highlight: screens != .none && screens != .briefly)
                    }
                    if let value = answers.screensLastUsedAt {
                        PreSleepRow(label: "Last Screen Use", value: shortTimeFormatter.string(from: value), icon: "clock", highlight: true)
                    }

                    if let temp = answers.roomTemp {
                        PreSleepRow(label: "Room Temp", value: temp.displayText, icon: "thermometer.medium")
                    }
                    if let noise = answers.noiseLevel {
                        PreSleepRow(label: "Noise Level", value: noise.displayText, icon: "speaker.wave.2.fill")
                    }
                    if let aids = answers.sleepAidDisplayText {
                        PreSleepRow(label: "Sleep Aids", value: aids, icon: "moon.stars")
                    }
                    if let notes = answers.notes, !notes.isEmpty {
                        PreSleepRow(label: "Notes", value: notes, icon: "square.and.pencil")
                    }

                    if let pain = answers.bodyPain, pain != .none {
                        PreSleepRow(label: "Body Pain", value: pain.displayText, icon: "bandage.fill", highlight: true)
                    }
                }
            } else if preSleepLog == nil {
                Text("No pre-sleep log recorded for this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }

            if !medicationEntries.isEmpty {
                if preSleepLog == nil || preSleepLog?.completionState == "skipped" {
                    Divider()
                }
                ForEach(Array(medicationEntries.enumerated()), id: \.element.id) { index, entry in
                    PreSleepRow(
                        label: medicationEntries.count == 1 ? "Medication" : "Medication \(index + 1)",
                        value: formattedMedicationEntry(entry),
                        icon: "pills.fill",
                        highlight: true
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func formatStressLevel(_ level: Int) -> String {
        switch level {
        case 0: return "None"
        case 1: return "Low"
        case 2: return "Mild"
        case 3: return "Medium"
        case 4: return "High"
        case 5: return "Very High"
        default: return "\(level)/5"
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var shortTimeFormatter: DateFormatter {
        AppFormatters.shortTime
    }

    private func formatDrinks(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded())) drinks"
        }
        return String(format: "%.1f drinks", value)
    }

    private func formattedMedicationEntry(_ entry: MedicationEntry) -> String {
        let dose: String
        if let medication = MedicationConfig.type(for: entry.medicationId),
           medication.category == .sodiumOxybate {
            dose = String(format: "%.2f g", Double(entry.doseMg) / 1000.0)
        } else {
            dose = "\(entry.doseMg) mg"
        }

        var value = "\(entry.displayName) \(dose) at \(shortTimeFormatter.string(from: entry.takenAtUTC))"
        if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            value += " (\(notes))"
        }
        return value
    }

    private func plannedDoseValueText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.grouping(.automatic))) mg"
    }
}

struct PreSleepRow: View {
    let label: String
    let value: String
    let icon: String
    var highlight: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(highlight ? .orange : .blue)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(highlight ? .orange : .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
