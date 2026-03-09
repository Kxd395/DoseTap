//
//  NightReviewView.swift
//  DoseTap
//
//  Comprehensive night review dashboard showing:
//  - Pre-Sleep Log answers
//  - Morning Check-in answers
//  - Dose timing (Dose 1 → Dose 2 interval)
//  - Sleep events (bathroom, wake events, etc.)
//  - Apple Health sleep data
//  - WHOOP sleep/recovery data
//

import Foundation
import SwiftUI
import DoseCore

// MARK: - Night Review View
struct NightReviewView: View {
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var selectedSessionKey: String
    @State private var availableSessions: [String] = []
    
    init(sessionKey: String? = nil) {
        let defaultKey = SessionRepository.shared.currentSessionKey
        _selectedSessionKey = State(initialValue: sessionKey ?? defaultKey)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Session Picker
                    SessionPickerCard(
                        selectedSession: $selectedSessionKey,
                        availableSessions: availableSessions
                    )
                    
                    // Dose Timing Summary
                    DoseTimingCard(sessionKey: selectedSessionKey)
                    
                    // Night Score
                    NightScoreCard(sessionKey: selectedSessionKey)
                    
                    // Pre-Sleep Log Section
                    PreSleepLogCard(sessionKey: selectedSessionKey)
                    
                    // Morning Check-in Section
                    MorningCheckInCard(sessionKey: selectedSessionKey)
                    
                    // Sleep Events Timeline
                    SleepEventsCard(sessionKey: selectedSessionKey)
                    
                    // Health Integrations
                    HealthDataCard(sessionKey: selectedSessionKey)
                    
                    // Export Button
                    ExportCard(sessionKey: selectedSessionKey)
                }
                .padding()
            }
            .navigationTitle("Night Review")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { loadAvailableSessions() }
        }
    }
    
    private func loadAvailableSessions() {
        // Get last 30 session keys
        availableSessions = sessionRepo.getRecentSessionKeys(limit: 30)
        if !availableSessions.contains(selectedSessionKey), let first = availableSessions.first {
            selectedSessionKey = first
        }
    }
}

// MARK: - Session Picker
struct SessionPickerCard: View {
    @Binding var selectedSession: String
    let availableSessions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Night")
                .font(.headline)
            
            Picker("Session", selection: $selectedSession) {
                ForEach(availableSessions, id: \.self) { session in
                    Text(formatSessionDate(session)).tag(session)
                }
            }
            .pickerStyle(.menu)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func formatSessionDate(_ key: String) -> String {
        guard let date = AppFormatters.sessionDate.date(from: key) else { return key }
        return AppFormatters.weekdayMedium.string(from: date)
    }
}

// MARK: - Dose Timing Card
struct DoseTimingCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    private var doseLog: StoredDoseLog? {
        sessionRepo.fetchDoseLog(forSession: sessionKey)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("💊 Dose Timing")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            
            VStack(spacing: 8) {
                DoseTimeRow(label: "Dose 1", time: doseLog?.dose1Time, icon: "1.circle.fill")
                DoseTimeRow(label: "Dose 2", time: doseLog?.dose2Time, icon: "2.circle.fill", skipped: doseLog?.dose2Skipped ?? false)
                
                if let intervalMins = doseLog?.intervalMinutes {
                    Divider()
                    HStack {
                        Text("Interval")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatInterval(Double(intervalMins) * 60))
                            .font(.headline)
                            .foregroundColor(intervalColor(Double(intervalMins) * 60))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            if doseLog?.dose2Skipped == true {
                return ("Skipped", .orange)
            } else if doseLog?.dose2Time != nil {
                if let intervalMins = doseLog?.intervalMinutes {
                    if intervalMins >= 150 && intervalMins <= 240 {
                        return ("Optimal", .green)
                    } else if intervalMins >= 120 {
                        return ("Early", .orange)
                    } else {
                        return ("Off-target", .red)
                    }
                }
                return ("Complete", .green)
            } else if doseLog?.dose1Time != nil {
                return ("In Progress", .blue)
            } else {
                return ("Not Started", .gray)
            }
        }()
        
        return Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
    
    private func formatInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let mins = (Int(interval) % 3600) / 60
        return "\(hours)h \(mins)m"
    }
    
    private func intervalColor(_ interval: TimeInterval) -> Color {
        let mins = interval / 60
        if mins >= 150 && mins <= 240 { return .green }
        if mins >= 120 { return .orange }
        return .red
    }
}

struct DoseTimeRow: View {
    let label: String
    let time: Date?
    let icon: String
    var skipped: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(skipped ? .orange : .blue)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            if skipped {
                Text("Skipped")
                    .foregroundColor(.orange)
            } else if let time = time {
                Text(time, style: .time)
                    .font(.headline)
            } else {
                Text("—")
                    .foregroundColor(.gray)
            }
        }
    }
}

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
                    // Timing & Stress
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
                    
                    // Substances
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
                    
                    // Activity & Naps
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
                    
                    // Environment
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
                    
                    // Pain
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
    
    // Format helpers
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

// MARK: - Morning Check-in Card
struct MorningCheckInCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    private var checkIn: StoredMorningCheckIn? {
        sessionRepo.fetchMorningCheckIn(for: sessionKey)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("☀️ Morning Check-in")
                    .font(.headline)
                Spacer()
                if checkIn != nil {
                    Text("Completed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                } else {
                    Text("Not recorded")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            if let ci = checkIn {
                VStack(spacing: 8) {
                    // Core metrics
                    MorningRow(label: "Sleep Quality", value: "\(ci.sleepQuality)/5 ⭐", icon: "star.fill")
                    MorningRow(label: "Feel Rested", value: ci.feelRested, icon: "battery.100.bolt")
                    MorningRow(label: "Grogginess", value: ci.grogginess, icon: "cloud.fog.fill")
                    MorningRow(label: "Sleep Inertia", value: ci.sleepInertiaDuration, icon: "timer")
                    
                    Divider()
                    
                    // Mental state
                    MorningRow(label: "Mental Clarity", value: "\(ci.mentalClarity)/5", icon: "lightbulb.fill")
                    MorningRow(label: "Mood", value: ci.mood, icon: "face.smiling")
                    MorningRow(label: "Anxiety", value: ci.anxietyLevel, icon: "heart.text.square")
                    if let stressLevel = ci.stressLevel {
                        MorningRow(label: "Stress Level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)", icon: "brain.head.profile")
                    }
                    if !ci.resolvedStressDrivers.isEmpty {
                        MorningRow(label: "Stressors", value: ci.resolvedStressDrivers.map(\.displayText).joined(separator: ", "), icon: "exclamationmark.triangle")
                    }
                    if let progression = ci.stressProgression {
                        MorningRow(label: "Stress Trend", value: progression.displayText, icon: "chart.line.uptrend.xyaxis")
                    }
                    MorningRow(label: "Readiness", value: "\(ci.readinessForDay)/5", icon: "figure.walk")
                    
                    // XYWAV-specific symptoms
                    if ci.hadSleepParalysis || ci.hadHallucinations || ci.hadAutomaticBehavior || ci.fellOutOfBed || ci.hadConfusionOnWaking {
                        Divider()
                        Text("Symptoms Reported")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if ci.hadSleepParalysis {
                            SymptomRow(symptom: "Sleep Paralysis")
                        }
                        if ci.hadHallucinations {
                            SymptomRow(symptom: "Hallucinations")
                        }
                        if ci.hadAutomaticBehavior {
                            SymptomRow(symptom: "Automatic Behavior")
                        }
                        if ci.fellOutOfBed {
                            SymptomRow(symptom: "Fell Out of Bed")
                        }
                        if ci.hadConfusionOnWaking {
                            SymptomRow(symptom: "Confusion on Waking")
                        }
                    }
                    
                    // Notes
                    if ci.stressNotes != nil || (ci.notes?.isEmpty == false) {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            if let stressNotes = ci.stressNotes {
                                Text("Stress Notes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(stressNotes)
                                    .font(.subheadline)
                            }
                            if let notes = ci.notes, !notes.isEmpty {
                                if ci.stressNotes != nil {
                                    Divider()
                                }
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(notes)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                Text("No morning check-in recorded for this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct MorningRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct SymptomRow: View {
    let symptom: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(symptom)
                .foregroundColor(.red)
        }
        .font(.subheadline)
    }
}

// MARK: - Sleep Events Card
struct SleepEventsCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    private var events: [StoredSleepEvent] {
        sessionRepo.fetchSleepEventsLocal(for: sessionKey)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📝 Sleep Events")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if events.isEmpty {
                Text("No events logged for this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(events, id: \.id) { event in
                    SleepEventRow(event: event)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct SleepEventRow: View {
    let event: StoredSleepEvent
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                .frame(width: 12, height: 12)
            
            Text(event.eventType.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline)
            
            Spacer()
            
            Text(event.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Night Score Card
struct NightScoreCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var result: NightScoreResult? {
        let doseLog = sessionRepo.fetchDoseLog(forSession: sessionKey)
        let events = sessionRepo.fetchSleepEventsLocal(for: sessionKey)
        let checkIn = sessionRepo.fetchMorningCheckIn(for: sessionKey)
        let hasLightsOut = events.contains { $0.eventType == "lights_out" }
        let hasWakeFinal = events.contains { $0.eventType == "wake_final" }
        let interval: Double? = doseLog?.intervalMinutes.map { Double($0) }

        let input = NightScoreInput(
            intervalMinutes: interval,
            dose2Skipped: doseLog?.dose2Skipped ?? false,
            dose1Taken: doseLog?.dose1Time != nil,
            dose2Taken: doseLog?.dose2Time != nil,
            checkInCompleted: checkIn != nil,
            lightsOutLogged: hasLightsOut,
            wakeFinalLogged: hasWakeFinal
        )
        return NightScoreCalculator.calculate(input)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🌙 Night Score")
                    .font(.headline)
                Spacer()
                if let r = result {
                    Text(r.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(labelColor(r.label))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(labelColor(r.label).opacity(0.15))
                        .cornerRadius(8)
                }
            }

            if let r = result {
                // Score circle
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(scoreColor(r.score).opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        Circle()
                            .trim(from: 0, to: Double(r.score) / 100.0)
                            .stroke(scoreColor(r.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 80, height: 80)
                        VStack(spacing: 0) {
                            Text("\(r.score)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }

                // Component breakdown
                VStack(spacing: 6) {
                    componentRow("Interval Accuracy", value: r.components.intervalAccuracy, weight: "40%")
                    componentRow("Dose Completeness", value: r.components.doseCompleteness, weight: "25%")
                    componentRow("Session Logging", value: r.components.sessionCompleteness, weight: "20%")
                    if let sq = r.components.sleepQuality {
                        componentRow("Sleep Quality", value: sq, weight: "15%")
                    } else {
                        HStack {
                            Text("Sleep Quality")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("No data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No dose data to calculate a score")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func componentRow(_ label: String, value: Double, weight: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(value))
                        .frame(width: geo.size.width * value, height: 6)
                }
            }
            .frame(width: 80, height: 6)
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }

    private func labelColor(_ label: String) -> Color {
        switch label {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }

    private func barColor(_ value: Double) -> Color {
        switch value {
        case 0.85...1.0: return .green
        case 0.7..<0.85: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }
}

// MARK: - Export Card
struct ExportCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var showingShareSheet = false
    @State private var exportContent: String = ""

    private var doseLog: StoredDoseLog? {
        sessionRepo.fetchDoseLog(forSession: sessionKey)
    }

    private var preSleepLog: StoredPreSleepLog? {
        sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionKey)
    }

    private var morningCheckIn: StoredMorningCheckIn? {
        sessionRepo.fetchMorningCheckIn(for: sessionKey)
    }

    private var sleepEvents: [StoredSleepEvent] {
        sessionRepo.fetchSleepEventsLocal(for: sessionKey).sorted { $0.timestamp < $1.timestamp }
    }

    private var medicationEntries: [MedicationEntry] {
        sessionRepo.listMedicationEntries(for: sessionKey).sorted { $0.takenAtUTC < $1.takenAtUTC }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📤 Export")
                .font(.headline)
            
            Text("Export this night's data for your sleep specialist or personal records.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button {
                    exportContent = generateExportContent(format: .text)
                    showingShareSheet = true
                } label: {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    exportContent = generateExportContent(format: .csv)
                    showingShareSheet = true
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .sheet(isPresented: $showingShareSheet) {
            ActivityViewController(activityItems: [exportContent])
        }
    }
    
    enum ExportFormat { case text, csv }
    
    private func generateExportContent(format: ExportFormat) -> String {
        switch format {
        case .text:
            return generateTextExport()
        case .csv:
            return generateCSVExport()
        }
    }

    private func generateTextExport() -> String {
        var lines: [String] = [
            "DoseTap Night Report",
            "Session: \(sessionDateLabel)",
            "Session Key: \(sessionKey)",
            "Generated: \(AppFormatters.mediumDateTime.string(from: Date()))"
        ]

        lines.append("")
        lines.append("Dose Timing")
        if let doseLog {
            appendTextField(&lines, label: "Dose 1", value: formatTime(doseLog.dose1Time))
            appendTextField(&lines, label: "Dose 2", value: doseLog.dose2Skipped ? "Skipped" : formatOptionalTime(doseLog.dose2Time))
            appendTextField(&lines, label: "Dose 2 Skipped", value: formatBoolean(doseLog.dose2Skipped))
            appendTextField(&lines, label: "Interval", value: doseLog.intervalMinutes.map(formatInterval))
            appendTextField(&lines, label: "Snooze Count", value: "\(doseLog.snoozeCount)")
        } else {
            lines.append("- No dose log recorded")
        }

        lines.append("")
        lines.append("Pre-Sleep Log")
        if let log = preSleepLog {
            appendTextField(&lines, label: "Status", value: log.completionState == "skipped" ? "Skipped" : "Completed")
            appendTextField(&lines, label: "Logged At", value: formatStoredTimestamp(log.createdAtUtc))

            if let answers = log.answers, log.completionState != "skipped" {
                appendTextField(&lines, label: "Intended Sleep Time", value: answers.intendedSleepTime?.displayText)
                if let stressLevel = answers.stressLevel {
                    appendTextField(&lines, label: "Stress Level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
                }
                appendTextField(&lines, label: "Stress Driver", value: answers.primaryStressDriver?.displayText)
                if !answers.resolvedStressDrivers.isEmpty {
                    appendTextField(&lines, label: "Stress Drivers", value: answers.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
                }
                appendTextField(&lines, label: "Stress Progression", value: answers.stressProgression?.displayText)
                appendTextField(&lines, label: "Stress Notes", value: nonEmpty(answers.stressNotes))
                appendTextField(&lines, label: "Later Reason", value: answers.laterReason?.displayText)
                appendTextField(&lines, label: "Body Pain", value: answers.bodyPain?.displayText)

                if let painEntries = answers.painEntries, !painEntries.isEmpty {
                    for (index, entry) in painEntries.enumerated() {
                        appendTextField(&lines, label: "Pain Entry \(index + 1)", value: formatPainEntry(entry))
                    }
                }

                if let painLocations = answers.painLocations, !painLocations.isEmpty {
                    appendTextField(&lines, label: "Pain Locations", value: painLocations.map(\.displayText).joined(separator: ", "))
                }

                appendTextField(&lines, label: "Pain Type", value: answers.painType?.displayText)
                appendTextField(&lines, label: "Caffeine Sources", value: answers.caffeineSourceDisplayText ?? answers.stimulants?.displayText)
                appendTextField(&lines, label: "Caffeine Last Intake", value: answers.caffeineLastIntakeAt.map(formatTime))
                appendTextField(&lines, label: "Caffeine Last Amount", value: answers.caffeineLastAmountMg.map { "\($0) oz" })
                appendTextField(&lines, label: "Caffeine Daily Total", value: answers.caffeineDailyTotalMg.map { "\($0) oz" })
                appendTextField(&lines, label: "Alcohol", value: answers.alcohol?.displayText)
                appendTextField(&lines, label: "Alcohol Last Drink", value: answers.alcoholLastDrinkAt.map(formatTime))
                appendTextField(&lines, label: "Alcohol Last Amount", value: answers.alcoholLastAmountDrinks.map(formatDrinks))
                appendTextField(&lines, label: "Alcohol Daily Total", value: answers.alcoholDailyTotalDrinks.map(formatDrinks))
                appendTextField(&lines, label: "Exercise", value: answers.exercise?.displayText)
                appendTextField(&lines, label: "Exercise Type", value: answers.exerciseType?.displayText)
                appendTextField(&lines, label: "Exercise Last At", value: answers.exerciseLastAt.map(formatTime))
                appendTextField(&lines, label: "Exercise Duration", value: answers.exerciseDurationMinutes.map { "\($0) min" })
                appendTextField(&lines, label: "Nap Today", value: answers.napToday?.displayText)
                appendTextField(&lines, label: "Nap Count", value: answers.napCount.map { String($0) })
                appendTextField(&lines, label: "Nap Total Minutes", value: answers.napTotalMinutes.map { "\($0) min" })
                appendTextField(&lines, label: "Last Nap End", value: answers.napLastEndAt.map(formatTime))
                appendTextField(&lines, label: "Late Meal", value: answers.lateMeal?.displayText)
                appendTextField(&lines, label: "Late Meal Ended", value: answers.lateMealEndedAt.map(formatTime))
                appendTextField(&lines, label: "Screens In Bed", value: answers.screensInBed?.displayText)
                appendTextField(&lines, label: "Last Screen Use", value: answers.screensLastUsedAt.map(formatTime))
                appendTextField(&lines, label: "Room Temperature", value: answers.roomTemp?.displayText)
                appendTextField(&lines, label: "Noise Level", value: answers.noiseLevel?.displayText)
                appendTextField(&lines, label: "Sleep Aids", value: answers.sleepAidDisplayText ?? answers.sleepAids?.displayText)
                appendTextField(&lines, label: "Notes", value: nonEmpty(answers.notes))
            }
        } else {
            lines.append("- No pre-sleep log recorded")
        }

        lines.append("")
        lines.append("Medications")
        if medicationEntries.isEmpty {
            lines.append("- No medication entries logged")
        } else {
            for (index, entry) in medicationEntries.enumerated() {
                appendTextField(&lines, label: "Medication \(index + 1)", value: formattedMedicationEntry(entry))
            }
        }

        lines.append("")
        lines.append("Morning Check-In")
        if let checkIn = morningCheckIn {
            appendTextField(&lines, label: "Submitted At", value: AppFormatters.mediumDateTime.string(from: checkIn.timestamp))
            appendTextField(&lines, label: "Sleep Quality", value: "\(checkIn.sleepQuality)/5")
            appendTextField(&lines, label: "Feel Rested", value: humanize(checkIn.feelRested))
            appendTextField(&lines, label: "Grogginess", value: humanize(checkIn.grogginess))
            appendTextField(&lines, label: "Sleep Inertia", value: humanize(checkIn.sleepInertiaDuration))
            appendTextField(&lines, label: "Dream Recall", value: humanize(checkIn.dreamRecall))
            appendTextField(&lines, label: "Mental Clarity", value: "\(checkIn.mentalClarity)/5")
            appendTextField(&lines, label: "Mood", value: humanize(checkIn.mood))
            appendTextField(&lines, label: "Anxiety", value: humanize(checkIn.anxietyLevel))
            if let stressLevel = checkIn.stressLevel {
                appendTextField(&lines, label: "Stress Level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
            }
            if !checkIn.resolvedStressDrivers.isEmpty {
                appendTextField(&lines, label: "Stress Drivers", value: checkIn.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
            }
            appendTextField(&lines, label: "Stress Progression", value: checkIn.stressProgression?.displayText)
            appendTextField(&lines, label: "Stress Notes", value: checkIn.stressNotes)
            appendTextField(&lines, label: "Readiness", value: "\(checkIn.readinessForDay)/5")

            let narcolepsySymptoms = formattedNarcolepsySymptoms(checkIn)
            appendTextField(&lines, label: "Narcolepsy Symptoms", value: narcolepsySymptoms.isEmpty ? "None" : narcolepsySymptoms.joined(separator: ", "))

            if checkIn.hasPhysicalSymptoms {
                let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
                appendTextField(&lines, label: "Physical Symptoms", value: "Yes")
                appendTextField(&lines, label: "Pain Severity", value: (physical["painSeverity"] as? Int).map { "\($0)/10" })
                appendTextField(&lines, label: "Pain Type", value: (physical["painType"] as? String).map(humanize))
                appendTextField(&lines, label: "Muscle Stiffness", value: (physical["muscleStiffness"] as? String).map(humanize))
                appendTextField(&lines, label: "Muscle Soreness", value: (physical["muscleSoreness"] as? String).map(humanize))
                appendTextField(&lines, label: "Headache", value: (physical["hasHeadache"] as? Bool).map(formatBoolean))
                appendTextField(&lines, label: "Headache Severity", value: (physical["headacheSeverity"] as? String).map(humanize))
                appendTextField(&lines, label: "Headache Location", value: (physical["headacheLocation"] as? String).map(humanize))

                let painEntries = formattedMorningPainEntries(from: physical)
                if !painEntries.isEmpty {
                    for (index, entry) in painEntries.enumerated() {
                        appendTextField(&lines, label: "Physical Pain Entry \(index + 1)", value: entry)
                    }
                } else if let painLocations = physical["painLocations"] as? [String], !painLocations.isEmpty {
                    appendTextField(&lines, label: "Pain Locations", value: painLocations.map(humanize).joined(separator: ", "))
                }

                appendTextField(&lines, label: "Physical Notes", value: nonEmpty(physical["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Physical Symptoms", value: "No")
            }

            if checkIn.hasRespiratorySymptoms {
                let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
                appendTextField(&lines, label: "Respiratory Symptoms", value: "Yes")
                appendTextField(&lines, label: "Congestion", value: (respiratory["congestion"] as? String).map(humanize))
                appendTextField(&lines, label: "Throat Condition", value: (respiratory["throatCondition"] as? String).map(humanize))
                appendTextField(&lines, label: "Cough Type", value: (respiratory["coughType"] as? String).map(humanize))
                appendTextField(&lines, label: "Sinus Pressure", value: (respiratory["sinusPressure"] as? String).map(humanize))
                appendTextField(&lines, label: "Feeling Feverish", value: (respiratory["feelingFeverish"] as? Bool).map(formatBoolean))
                appendTextField(&lines, label: "Sickness Level", value: (respiratory["sicknessLevel"] as? String).map(humanize))
                appendTextField(&lines, label: "Respiratory Notes", value: nonEmpty(respiratory["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Respiratory Symptoms", value: "No")
            }

            if checkIn.usedSleepTherapy {
                let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
                appendTextField(&lines, label: "Sleep Therapy Used", value: "Yes")
                appendTextField(&lines, label: "Sleep Therapy Device", value: (therapy["device"] as? String).map(humanize))
                appendTextField(&lines, label: "Sleep Therapy Compliance", value: (therapy["compliance"] as? Int).map { "\($0)/10" })
                appendTextField(&lines, label: "Sleep Therapy Notes", value: nonEmpty(therapy["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Sleep Therapy Used", value: "No")
            }

            appendTextField(&lines, label: "Notes", value: nonEmpty(checkIn.notes))
        } else {
            lines.append("- No morning check-in recorded")
        }

        lines.append("")
        lines.append("Sleep Events")
        if sleepEvents.isEmpty {
            lines.append("- No sleep events logged")
        } else {
            appendTextField(&lines, label: "Event Count", value: "\(sleepEvents.count)")
            for event in sleepEvents {
                appendTextField(&lines, label: formatTime(event.timestamp), value: formattedEventDetails(event))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func generateCSVExport() -> String {
        var rows = ["session_key,session_date,section,field,value"]

        appendCSVRow(&rows, section: "meta", field: "generated_at", value: AppFormatters.mediumDateTime.string(from: Date()))
        appendCSVRow(&rows, section: "dose", field: "dose_1_time", value: doseLog.map { formatTime($0.dose1Time) })
        appendCSVRow(&rows, section: "dose", field: "dose_2_time", value: doseLog?.dose2Skipped == true ? "Skipped" : doseLog?.dose2Time.map(formatTime))
        appendCSVRow(&rows, section: "dose", field: "dose_2_skipped", value: doseLog.map { formatBoolean($0.dose2Skipped) })
        appendCSVRow(&rows, section: "dose", field: "interval", value: doseLog?.intervalMinutes.map(formatInterval))
        appendCSVRow(&rows, section: "dose", field: "snooze_count", value: doseLog.map { String($0.snoozeCount) })

        if let log = preSleepLog {
            appendCSVRow(&rows, section: "pre_sleep", field: "status", value: log.completionState == "skipped" ? "Skipped" : "Completed")
            appendCSVRow(&rows, section: "pre_sleep", field: "logged_at", value: formatStoredTimestamp(log.createdAtUtc))

            if let answers = log.answers, log.completionState != "skipped" {
                appendCSVRow(&rows, section: "pre_sleep", field: "intended_sleep_time", value: answers.intendedSleepTime?.displayText)
                if let stressLevel = answers.stressLevel {
                    appendCSVRow(&rows, section: "pre_sleep", field: "stress_level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
                }
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_driver", value: answers.primaryStressDriver?.displayText)
                if !answers.resolvedStressDrivers.isEmpty {
                    appendCSVRow(&rows, section: "pre_sleep", field: "stress_drivers", value: answers.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
                }
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_progression", value: answers.stressProgression?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_notes", value: nonEmpty(answers.stressNotes))
                appendCSVRow(&rows, section: "pre_sleep", field: "later_reason", value: answers.laterReason?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "body_pain", value: answers.bodyPain?.displayText)

                if let painEntries = answers.painEntries {
                    for (index, entry) in painEntries.enumerated() {
                        appendCSVRow(&rows, section: "pre_sleep", field: "pain_entry_\(index + 1)", value: formatPainEntry(entry))
                    }
                }

                if let painLocations = answers.painLocations, !painLocations.isEmpty {
                    appendCSVRow(&rows, section: "pre_sleep", field: "pain_locations", value: painLocations.map(\.displayText).joined(separator: ", "))
                }

                appendCSVRow(&rows, section: "pre_sleep", field: "pain_type", value: answers.painType?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "stimulants_summary", value: answers.stimulants?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_sources", value: answers.caffeineSourceDisplayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_last_intake", value: answers.caffeineLastIntakeAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_last_amount_oz", value: answers.caffeineLastAmountMg.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_daily_total_oz", value: answers.caffeineDailyTotalMg.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol", value: answers.alcohol?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_last_drink", value: answers.alcoholLastDrinkAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_last_amount", value: answers.alcoholLastAmountDrinks.map(formatDrinks))
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_daily_total", value: answers.alcoholDailyTotalDrinks.map(formatDrinks))
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise", value: answers.exercise?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_type", value: answers.exerciseType?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_last_at", value: answers.exerciseLastAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_duration_minutes", value: answers.exerciseDurationMinutes.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_today", value: answers.napToday?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_count", value: answers.napCount.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_total_minutes", value: answers.napTotalMinutes.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_last_end", value: answers.napLastEndAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "late_meal", value: answers.lateMeal?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "late_meal_ended", value: answers.lateMealEndedAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "screens_in_bed", value: answers.screensInBed?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "screens_last_used", value: answers.screensLastUsedAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "room_temp", value: answers.roomTemp?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "noise_level", value: answers.noiseLevel?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "sleep_aids", value: answers.sleepAidDisplayText ?? answers.sleepAids?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "notes", value: nonEmpty(answers.notes))
            }
        }

        if medicationEntries.isEmpty {
            appendCSVRow(&rows, section: "medication", field: "entries", value: "None")
        } else {
            for (index, entry) in medicationEntries.enumerated() {
                appendCSVRow(&rows, section: "medication", field: "entry_\(index + 1)", value: formattedMedicationEntry(entry))
            }
        }

        if let checkIn = morningCheckIn {
            appendCSVRow(&rows, section: "morning", field: "submitted_at", value: AppFormatters.mediumDateTime.string(from: checkIn.timestamp))
            appendCSVRow(&rows, section: "morning", field: "sleep_quality", value: "\(checkIn.sleepQuality)/5")
            appendCSVRow(&rows, section: "morning", field: "feel_rested", value: humanize(checkIn.feelRested))
            appendCSVRow(&rows, section: "morning", field: "grogginess", value: humanize(checkIn.grogginess))
            appendCSVRow(&rows, section: "morning", field: "sleep_inertia", value: humanize(checkIn.sleepInertiaDuration))
            appendCSVRow(&rows, section: "morning", field: "dream_recall", value: humanize(checkIn.dreamRecall))
            appendCSVRow(&rows, section: "morning", field: "mental_clarity", value: "\(checkIn.mentalClarity)/5")
            appendCSVRow(&rows, section: "morning", field: "mood", value: humanize(checkIn.mood))
            appendCSVRow(&rows, section: "morning", field: "anxiety", value: humanize(checkIn.anxietyLevel))
            if let stressLevel = checkIn.stressLevel {
                appendCSVRow(&rows, section: "morning", field: "stress_level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
            }
            if !checkIn.resolvedStressDrivers.isEmpty {
                appendCSVRow(&rows, section: "morning", field: "stress_drivers", value: checkIn.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
            }
            appendCSVRow(&rows, section: "morning", field: "stress_progression", value: checkIn.stressProgression?.displayText)
            appendCSVRow(&rows, section: "morning", field: "stress_notes", value: checkIn.stressNotes)
            appendCSVRow(&rows, section: "morning", field: "readiness", value: "\(checkIn.readinessForDay)/5")

            let narcolepsySymptoms = formattedNarcolepsySymptoms(checkIn)
            appendCSVRow(&rows, section: "morning", field: "narcolepsy_symptoms", value: narcolepsySymptoms.isEmpty ? "None" : narcolepsySymptoms.joined(separator: ", "))

            if checkIn.hasPhysicalSymptoms {
                let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
                appendCSVRow(&rows, section: "morning", field: "physical_symptoms", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "pain_severity", value: (physical["painSeverity"] as? Int).map { "\($0)/10" })
                appendCSVRow(&rows, section: "morning", field: "pain_type", value: (physical["painType"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "muscle_stiffness", value: (physical["muscleStiffness"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "muscle_soreness", value: (physical["muscleSoreness"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "headache", value: (physical["hasHeadache"] as? Bool).map(formatBoolean))
                appendCSVRow(&rows, section: "morning", field: "headache_severity", value: (physical["headacheSeverity"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "headache_location", value: (physical["headacheLocation"] as? String).map(humanize))

                let painEntries = formattedMorningPainEntries(from: physical)
                for (index, entry) in painEntries.enumerated() {
                    appendCSVRow(&rows, section: "morning", field: "physical_pain_entry_\(index + 1)", value: entry)
                }

                if let painLocations = physical["painLocations"] as? [String], !painLocations.isEmpty {
                    appendCSVRow(&rows, section: "morning", field: "pain_locations", value: painLocations.map(humanize).joined(separator: ", "))
                }

                appendCSVRow(&rows, section: "morning", field: "physical_notes", value: nonEmpty(physical["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "physical_symptoms", value: "No")
            }

            if checkIn.hasRespiratorySymptoms {
                let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
                appendCSVRow(&rows, section: "morning", field: "respiratory_symptoms", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "congestion", value: (respiratory["congestion"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "throat_condition", value: (respiratory["throatCondition"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "cough_type", value: (respiratory["coughType"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "sinus_pressure", value: (respiratory["sinusPressure"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "feeling_feverish", value: (respiratory["feelingFeverish"] as? Bool).map(formatBoolean))
                appendCSVRow(&rows, section: "morning", field: "sickness_level", value: (respiratory["sicknessLevel"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "respiratory_notes", value: nonEmpty(respiratory["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "respiratory_symptoms", value: "No")
            }

            if checkIn.usedSleepTherapy {
                let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_used", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_device", value: (therapy["device"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_compliance", value: (therapy["compliance"] as? Int).map { "\($0)/10" })
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_notes", value: nonEmpty(therapy["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_used", value: "No")
            }

            appendCSVRow(&rows, section: "morning", field: "notes", value: nonEmpty(checkIn.notes))
        }

        appendCSVRow(&rows, section: "sleep_events", field: "count", value: "\(sleepEvents.count)")
        for (index, event) in sleepEvents.enumerated() {
            appendCSVRow(&rows, section: "sleep_events", field: "event_\(index + 1)", value: formattedEvent(event))
        }

        return rows.joined(separator: "\n")
    }

    private var sessionDateLabel: String {
        guard let date = AppFormatters.sessionDate.date(from: sessionKey) else { return sessionKey }
        return AppFormatters.fullDate.string(from: date)
    }

    private func appendTextField(_ lines: inout [String], label: String, value: String?) {
        guard let value = nonEmpty(value) else { return }
        lines.append("- \(label): \(value)")
    }

    private func appendCSVRow(_ rows: inout [String], section: String, field: String, value: String?) {
        guard let value = nonEmpty(value) else { return }
        let columns = [sessionKey, sessionDateLabel, section, field, value].map(csvEscaped)
        rows.append(columns.joined(separator: ","))
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func formatStoredTimestamp(_ value: String) -> String {
        if let date = AppFormatters.parseISO8601Flexible(value) {
            return AppFormatters.mediumDateTime.string(from: date)
        }
        return value
    }

    private func formatTime(_ date: Date) -> String {
        AppFormatters.mediumDateTime.string(from: date)
    }

    private func formatOptionalTime(_ date: Date?) -> String {
        guard let date else { return "Not recorded" }
        return formatTime(date)
    }

    private func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
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

    private func formatDrinks(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded())) drinks"
        }
        return String(format: "%.1f drinks", value)
    }

    private func formatBoolean(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func formattedEvent(_ event: StoredSleepEvent) -> String {
        let parts = [
            AppFormatters.mediumDateTime.string(from: event.timestamp),
            formattedEventDetails(event)
        ]

        return parts.joined(separator: " | ")
    }

    private func formattedEventDetails(_ event: StoredSleepEvent) -> String {
        var parts = [
            humanize(event.eventType)
        ]

        if let notes = nonEmpty(event.notes) {
            parts.append(notes)
        }

        return parts.joined(separator: " | ")
    }

    private func formattedMedicationEntry(_ entry: MedicationEntry) -> String {
        let dose: String
        if let medication = MedicationConfig.type(for: entry.medicationId),
           medication.category == .sodiumOxybate {
            dose = String(format: "%.2f g", Double(entry.doseMg) / 1000.0)
        } else {
            dose = "\(entry.doseMg) mg"
        }

        var value = "\(entry.displayName) \(dose) at \(formatTime(entry.takenAtUTC))"
        if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            value += " (\(notes))"
        }
        return value
    }

    private func formatPainEntry(_ entry: PreSleepLogAnswers.PainEntry) -> String {
        var parts = ["\(entry.area.displayText) (\(entry.side.displayText))", "Intensity \(entry.intensity)/10"]

        if !entry.sensations.isEmpty {
            parts.append(entry.sensations.map(\.displayText).joined(separator: ", "))
        }
        if let pattern = entry.pattern {
            parts.append(pattern.displayText)
        }
        if let notes = nonEmpty(entry.notes) {
            parts.append(notes)
        }

        return parts.joined(separator: " | ")
    }

    private func formattedNarcolepsySymptoms(_ checkIn: StoredMorningCheckIn) -> [String] {
        var values: [String] = []
        if checkIn.hadSleepParalysis { values.append("Sleep Paralysis") }
        if checkIn.hadHallucinations { values.append("Hallucinations") }
        if checkIn.hadAutomaticBehavior { values.append("Automatic Behavior") }
        if checkIn.fellOutOfBed { values.append("Fell Out Of Bed") }
        if checkIn.hadConfusionOnWaking { values.append("Confusion On Waking") }
        return values
    }

    private func formattedMorningPainEntries(from physical: [String: Any]) -> [String] {
        guard let entries = physical["painEntries"] as? [[String: Any]] else { return [] }

        return entries.compactMap { entry in
            let area = nonEmpty((entry["area"] as? String).map(humanize)) ?? "Unknown"
            let side = nonEmpty((entry["side"] as? String).map(humanize))
            let intensity = intValue(entry["intensity"])
            let sensations = (entry["sensations"] as? [String])?.map(humanize).joined(separator: ", ")
            let pattern = (entry["pattern"] as? String).map(humanize)
            let notes = nonEmpty(entry["notes"] as? String)

            var parts = [area + (side.map { " (\($0))" } ?? "")]
            if let intensity {
                parts.append("Intensity \(intensity)/10")
            }
            if let sensations = nonEmpty(sensations) {
                parts.append(sensations)
            }
            if let pattern = nonEmpty(pattern) {
                parts.append(pattern)
            }
            if let notes {
                parts.append(notes)
            }
            return parts.joined(separator: " | ")
        }
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        return nil
    }

    private func jsonDictionary(from raw: String?) -> [String: Any] {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func humanize(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )

        let acronyms = Set(["ahi", "apap", "bipap", "cpap", "rem"])

        return spaced
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                let value = String(token)
                return acronyms.contains(value.lowercased()) ? value.uppercased() : value.capitalized
            }
            .joined(separator: " ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Preview
#if DEBUG
struct NightReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NightReviewView()
    }
}
#endif
