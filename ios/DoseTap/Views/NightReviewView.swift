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
                    if let aids = answers.sleepAids {
                        PreSleepRow(label: "Sleep Aids", value: aids.displayText, icon: "moon.stars")
                    }
                    
                    // Pain (new 0-10 scale)
                    if let painLevel = answers.painLevel010, painLevel > 0 {
                        let painText: String = {
                            var text = "\(painLevel)/10"
                            if let locations = answers.painDetailedLocations, !locations.isEmpty {
                                let locationText = locations.prefix(2).map { $0.compactText }.joined(separator: ", ")
                                text += " – \(locationText)"
                                if locations.count > 2 { text += ", +\(locations.count - 2) more" }
                            }
                            return text
                        }()
                        PreSleepRow(label: "Body Pain", value: painText, icon: "bandage.fill", highlight: true)
                    }
                    // Fallback: Legacy pain (backwards compatibility only)
                    else if let pain = answers.legacyBodyPain, pain != .none {
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
    @StateObject private var dataStorage = DataStorageService.shared
    
    private var sessionData: DoseSessionData? {
        dataStorage.getAllSessions().first { $0.sessionKey == sessionKey }
    }

    private var healthData: HealthData? {
        sessionData?.healthData
    }

    private var whoopData: WHOOPData? {
        sessionData?.whoopData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 Health Integrations")
                .font(.headline)
            
            if healthData == nil && whoopData == nil {
                Text("No synced health data found for this night yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    HealthIntegrationRow(
                        source: "Apple Health",
                        icon: "heart.fill",
                        iconColor: .red,
                        data: appleHealthRows
                    )

                    Divider()

                    HealthIntegrationRow(
                        source: "WHOOP",
                        icon: "waveform.path.ecg",
                        iconColor: .green,
                        data: whoopRows
                    )
                }
            }
            
            Text("Sync from Settings -> Integrations, then refresh this report.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var appleHealthRows: [(String, String)] {
        guard let healthData else {
            return [("Status", "Not synced")]
        }
        return [
            ("Total Sleep", formatDuration(healthData.totalSleepTime)),
            ("Deep Sleep", formatDuration(healthData.deepSleepTime)),
            ("REM", formatDuration(healthData.remSleepTime))
        ]
    }

    private var whoopRows: [(String, String)] {
        guard let whoopData else {
            return [("Status", "Not synced")]
        }
        return [
            ("Recovery", whoopData.recoveryScore.map { "\($0)%" } ?? "—"),
            ("HRV", whoopData.hrv.map { String(format: "%.0f ms", $0) } ?? "—"),
            ("Sleep Score", whoopData.sleepScore.map(String.init) ?? "—")
        ]
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
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
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @StateObject private var dataStorage = DataStorageService.shared
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
        sessionRepo.fetchSleepEventsLocal(for: sessionKey)
    }

    private var sessionData: DoseSessionData? {
        dataStorage.getAllSessions().first { $0.sessionKey == sessionKey }
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
            return generateTextReport()
        case .csv:
            return generateCSVReport()
        }
    }

    private func generateTextReport() -> String {
        var lines: [String] = []
        lines.append("DoseTap Night Report")
        lines.append("Session: \(sessionKey)")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        lines.append("Dose Summary")
        if let doseLog {
            lines.append("- Dose 1: \(formatTime(doseLog.dose1Time))")
            if let dose2 = doseLog.dose2Time {
                lines.append("- Dose 2: \(formatTime(dose2))")
            } else {
                lines.append("- Dose 2: \(doseLog.dose2Skipped ? "Skipped" : "Not recorded")")
            }
            lines.append("- Snoozes: \(doseLog.snoozeCount)")
            if let interval = doseLog.intervalMinutes {
                lines.append("- Interval: \(interval) minutes")
            }
        } else {
            lines.append("- No dose log available")
        }
        lines.append("")
        lines.append("Pre-Sleep Log")
        if let preSleepLog {
            lines.append("- Completion: \(preSleepLog.completionState)")
            if let answers = preSleepLog.answers {
                lines.append("- Stress: \(answers.stressLevel.map(String.init) ?? "—")")
                lines.append("- Exercise: \(answers.exercise?.displayText ?? "—")")
                lines.append("- Nap: \(answers.napToday?.displayText ?? "—")")
                lines.append("- Screens: \(answers.screensInBed?.displayText ?? "—")")
            }
        } else {
            lines.append("- Not recorded")
        }
        lines.append("")
        lines.append("Morning Check-in")
        if let morningCheckIn {
            lines.append("- Sleep quality: \(morningCheckIn.sleepQuality)/5")
            lines.append("- Feel rested: \(morningCheckIn.feelRested)")
            lines.append("- Grogginess: \(morningCheckIn.grogginess)")
            lines.append("- Readiness: \(morningCheckIn.readinessForDay)/5")
        } else {
            lines.append("- Not recorded")
        }
        lines.append("")
        lines.append("Sleep Events (\(sleepEvents.count))")
        if sleepEvents.isEmpty {
            lines.append("- No events logged")
        } else {
            for event in sleepEvents {
                let display = event.eventType.replacingOccurrences(of: "_", with: " ").capitalized
                lines.append("- \(formatTime(event.timestamp))  \(display)")
            }
        }
        lines.append("")
        lines.append("Health Integrations")
        if let health = sessionData?.healthData {
            lines.append("- Apple Health total sleep: \(formatDuration(health.totalSleepTime))")
            lines.append("- Apple Health deep sleep: \(formatDuration(health.deepSleepTime))")
            lines.append("- Apple Health REM: \(formatDuration(health.remSleepTime))")
        } else {
            lines.append("- Apple Health: Not synced")
        }
        if let whoop = sessionData?.whoopData {
            lines.append("- WHOOP sleep score: \(whoop.sleepScore.map(String.init) ?? "—")")
            lines.append("- WHOOP recovery: \(whoop.recoveryScore.map { "\($0)%" } ?? "—")")
            lines.append("- WHOOP HRV: \(whoop.hrv.map { String(format: "%.0f ms", $0) } ?? "—")")
        } else {
            lines.append("- WHOOP: Not synced")
        }
        return lines.joined(separator: "\n")
    }

    private func generateCSVReport() -> String {
        var rows = ["section,key,value"]

        appendCSVRow(&rows, section: "session", key: "session_key", value: sessionKey)
        appendCSVRow(&rows, section: "session", key: "generated_at", value: Date().ISO8601Format())

        appendCSVRow(&rows, section: "dose", key: "dose1_time", value: doseLog.map { $0.dose1Time.ISO8601Format() } ?? "")
        appendCSVRow(&rows, section: "dose", key: "dose2_time", value: doseLog?.dose2Time?.ISO8601Format() ?? "")
        appendCSVRow(&rows, section: "dose", key: "dose2_skipped", value: doseLog?.dose2Skipped == true ? "1" : "0")
        appendCSVRow(&rows, section: "dose", key: "snooze_count", value: String(doseLog?.snoozeCount ?? 0))
        appendCSVRow(&rows, section: "dose", key: "interval_minutes", value: doseLog?.intervalMinutes.map(String.init) ?? "")

        appendCSVRow(&rows, section: "pre_sleep", key: "completion_state", value: preSleepLog?.completionState ?? "")
        appendCSVRow(&rows, section: "pre_sleep", key: "stress_level", value: preSleepLog?.answers?.stressLevel.map(String.init) ?? "")
        appendCSVRow(&rows, section: "pre_sleep", key: "exercise", value: preSleepLog?.answers?.exercise?.displayText ?? "")
        appendCSVRow(&rows, section: "pre_sleep", key: "nap", value: preSleepLog?.answers?.napToday?.displayText ?? "")
        appendCSVRow(&rows, section: "pre_sleep", key: "screens_in_bed", value: preSleepLog?.answers?.screensInBed?.displayText ?? "")

        appendCSVRow(&rows, section: "morning", key: "sleep_quality", value: morningCheckIn.map { String($0.sleepQuality) } ?? "")
        appendCSVRow(&rows, section: "morning", key: "feel_rested", value: morningCheckIn?.feelRested ?? "")
        appendCSVRow(&rows, section: "morning", key: "grogginess", value: morningCheckIn?.grogginess ?? "")
        appendCSVRow(&rows, section: "morning", key: "readiness", value: morningCheckIn.map { String($0.readinessForDay) } ?? "")

        for (index, event) in sleepEvents.enumerated() {
            appendCSVRow(&rows, section: "sleep_event", key: "event_\(index + 1)_type", value: event.eventType)
            appendCSVRow(&rows, section: "sleep_event", key: "event_\(index + 1)_timestamp", value: event.timestamp.ISO8601Format())
        }

        appendCSVRow(&rows, section: "health", key: "total_sleep_seconds", value: sessionData?.healthData?.totalSleepTime.map { String(Int($0)) } ?? "")
        appendCSVRow(&rows, section: "health", key: "deep_sleep_seconds", value: sessionData?.healthData?.deepSleepTime.map { String(Int($0)) } ?? "")
        appendCSVRow(&rows, section: "health", key: "rem_sleep_seconds", value: sessionData?.healthData?.remSleepTime.map { String(Int($0)) } ?? "")
        appendCSVRow(&rows, section: "whoop", key: "sleep_score", value: sessionData?.whoopData?.sleepScore.map(String.init) ?? "")
        appendCSVRow(&rows, section: "whoop", key: "recovery_score", value: sessionData?.whoopData?.recoveryScore.map(String.init) ?? "")
        appendCSVRow(&rows, section: "whoop", key: "hrv", value: sessionData?.whoopData?.hrv.map { String(format: "%.1f", $0) } ?? "")

        return rows.joined(separator: "\n")
    }

    private func appendCSVRow(_ rows: inout [String], section: String, key: String, value: String) {
        rows.append("\(escapeCSV(section)),\(escapeCSV(key)),\(escapeCSV(value))")
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Activity View Controller (Share Sheet)
#if canImport(UIKit)
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Preview
#if DEBUG
struct NightReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NightReviewView()
    }
}
#endif
