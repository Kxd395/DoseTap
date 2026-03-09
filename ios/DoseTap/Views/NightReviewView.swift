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

// MARK: - Preview
#if DEBUG
struct NightReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NightReviewView()
    }
}
#endif
