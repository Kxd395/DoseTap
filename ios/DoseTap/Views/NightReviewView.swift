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

import SwiftUI

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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
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
                        PreSleepRow(label: "Stress Level", value: formatStressLevel(stress), icon: "brain.head.profile")
                    }
                    if let intended = answers.intendedSleepTime {
                        PreSleepRow(label: "Sleep In", value: intended.displayText, icon: "moon.fill")
                    }
                    
                    // Substances
                    if let stimulants = answers.stimulants, stimulants != .none {
                        PreSleepRow(label: "Caffeine/Stimulants", value: stimulants.displayText, icon: "cup.and.saucer.fill", highlight: true)
                    }
                    if let alcohol = answers.alcohol, alcohol != .none {
                        PreSleepRow(label: "Alcohol", value: alcohol.displayText, icon: "wineglass.fill", highlight: true)
                    }
                    if let meal = answers.lateMeal, meal != .none {
                        PreSleepRow(label: "Late Meal", value: meal.displayText, icon: "fork.knife", highlight: true)
                    }
                    
                    // Activity & Naps
                    if let nap = answers.napToday, nap != .none {
                        PreSleepRow(label: "Nap Today", value: nap.displayText, icon: "bed.double.fill")
                    }
                    if let exercise = answers.exercise {
                        PreSleepRow(label: "Exercise", value: exercise.displayText, icon: "figure.run")
                    }
                    if let screens = answers.screensInBed, screens != .none {
                        PreSleepRow(label: "Screen Time", value: screens.displayText, icon: "iphone", highlight: screens != .none && screens != .briefly)
                    }
                    
                    // Environment
                    if let temp = answers.roomTemp {
                        PreSleepRow(label: "Room Temp", value: temp.displayText, icon: "thermometer.medium")
                    }
                    if let noise = answers.noiseLevel {
                        PreSleepRow(label: "Noise Level", value: noise.displayText, icon: "speaker.wave.2.fill")
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // Format helpers
    private func formatStressLevel(_ level: Int) -> String {
        let labels = ["None", "Low", "Moderate", "High", "Very High"]
        return level < labels.count ? labels[level] : "\(level)/4"
    }
}

struct PreSleepRow: View {
    let label: String
    let value: String
    let icon: String
    var highlight: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(highlight ? .orange : .blue)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(highlight ? .orange : .primary)
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
                    if let notes = ci.notes, !notes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(.subheadline)
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
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
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

// MARK: - Health Data Card
struct HealthDataCard: View {
    let sessionKey: String
    
    // TODO: Integrate with HealthKitManager and WHOOPManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 Health Integrations")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Apple Health
                HealthIntegrationRow(
                    source: "Apple Health",
                    icon: "heart.fill",
                    iconColor: .red,
                    data: [
                        ("Total Sleep", "7h 23m"),
                        ("Deep Sleep", "1h 45m"),
                        ("REM", "2h 10m")
                    ]
                )
                
                Divider()
                
                // WHOOP
                HealthIntegrationRow(
                    source: "WHOOP",
                    icon: "waveform.path.ecg",
                    iconColor: .green,
                    data: [
                        ("Recovery", "68%"),
                        ("HRV", "45ms"),
                        ("Sleep Score", "82")
                    ]
                )
            }
            
            Text("Sync health data in Settings → Integrations")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct HealthIntegrationRow: View {
    let source: String
    let icon: String
    let iconColor: Color
    let data: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(source)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 16) {
                ForEach(data, id: \.0) { item in
                    VStack(spacing: 2) {
                        Text(item.1)
                            .font(.headline)
                        Text(item.0)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Export Card
struct ExportCard: View {
    let sessionKey: String
    @State private var showingShareSheet = false
    @State private var exportContent: String = ""
    
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
            ShareSheet(items: [exportContent])
        }
    }
    
    enum ExportFormat { case text, csv }
    
    private func generateExportContent(format: ExportFormat) -> String {
        // TODO: Generate actual export content from session data
        return "DoseTap Night Report - \(sessionKey)\n\nExport your full night data for review."
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
