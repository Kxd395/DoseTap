import Foundation
import SwiftUI
import DoseCore

/// Counts recorded entries, never inferred awakenings or awake minutes.
struct BathroomLogSummary {
    let totalLogs: Int
    let nightsWithLogs: Int
    let recordedNights: Int

    init(nightEvents: [[StoredSleepEvent]]) {
        let counts = nightEvents.map { events in
            events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
        }
        totalLogs = counts.reduce(0, +)
        nightsWithLogs = counts.filter { $0 > 0 }.count
        recordedNights = counts.count
    }

    var valueText: String { recordedNights == 0 ? "No history" : "\(totalLogs) logged" }
    var coverageText: String {
        recordedNights == 0 ? "No recorded nights in this summary."
            : "\(nightsWithLogs) of \(recordedNights) recorded nights have bathroom logs."
    }
    var explanation: String {
        "\(coverageText) Logs do not measure awake time; no entry does not mean no awakening."
    }
}

/// Calculates descriptive metrics from historical session records.
@MainActor
public class InsightsCalculator: ObservableObject {
    
    static let shared = InsightsCalculator()
    private let repository: SessionRepository

    init(repository: SessionRepository = .shared) {
        self.repository = repository
    }
    
    // MARK: - Published Metrics
    @Published var onTimePercentage: Double = 0
    @Published var averageIntervalMinutes: Double = 0
    @Published var naturalWakePercentage: Double = 0
    @Published var wakeMethodSampleCount: Int = 0
    @Published var bathroomLogs = BathroomLogSummary(nightEvents: [])
    @Published var totalSessions: Int = 0
    @Published var completedSessions: Int = 0
    @Published var skippedSessions: Int = 0
    @Published var onTimeSessionCount: Int = 0
    @Published var intervalSampleCount: Int = 0
    
    // MARK: - Recent Sessions Data
    @Published var recentSessions: [SessionInsight] = []
    
    // MARK: - Session Insight Model
    struct SessionInsight: Identifiable {
        let id = UUID()
        let sessionDate: String
        let dose1Time: Date?
        let dose2Time: Date?
        let intervalMinutes: Int?
        let isOnTime: Bool  // Dose 2 within 150-240 min window
        let isSkipped: Bool
        let snoozeCount: Int
        let eventCount: Int
        let bathroomLogCount: Int
    }

    private enum DoseEventKind {
        case dose1
        case dose2
        case dose2Skipped
        case extraDose
        case other
    }

    private struct DerivedDoseMetrics {
        let dose1Time: Date?
        let dose2Time: Date?
        let dose2Skipped: Bool
    }

    private func normalizedDoseEventKind(_ rawType: String) -> DoseEventKind {
        let normalized = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            return .dose1
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken", "dose2_early", "dose_2_early", "dose2_late", "dose_2_late", "dose_2_(early)", "dose_2_(late)":
            return .dose2
        case "dose2_skipped", "dose_2_skipped", "dose2skipped", "dose_2_skipped_reason", "skip", "skipped":
            return .dose2Skipped
        case "extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken":
            return .extraDose
        default:
            return .other
        }
    }

    private func deriveDoseMetrics(from doseEvents: [DoseCore.StoredDoseEvent]) -> DerivedDoseMetrics {
        let sorted = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let dose1 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose1 }?.timestamp
        let dose2 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose2 }?.timestamp
        let skipped = sorted.contains { normalizedDoseEventKind($0.eventType) == .dose2Skipped }

        if dose1 == nil {
            let doseLike = sorted.filter {
                let kind = normalizedDoseEventKind($0.eventType)
                return kind == .dose1 || kind == .dose2 || kind == .extraDose
            }
            if let inferredDose1 = doseLike.first?.timestamp {
                let inferredDose2 = dose2 ?? (doseLike.count > 1 ? doseLike[1].timestamp : nil)
                return DerivedDoseMetrics(
                    dose1Time: inferredDose1,
                    dose2Time: inferredDose2,
                    dose2Skipped: skipped
                )
            }
        }

        return DerivedDoseMetrics(
            dose1Time: dose1,
            dose2Time: dose2,
            dose2Skipped: skipped
        )
    }
    
    // MARK: - Compute Insights
    
    /// Compute all insights from recent session history
    /// - Parameter days: Number of days to analyze (default 14)
    func computeInsights(days: Int = 14) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-bathroom-insights") {
            // Display-only fixture; never seeds source events or medication records.
            resetMetrics()
            totalSessions = 3
            let event = StoredSleepEvent(id: "insight-fixture", eventType: "Bathroom",
                timestamp: Date(timeIntervalSince1970: 0), sessionDate: "2026-09-08")
            bathroomLogs = BathroomLogSummary(nightEvents: [[event, event], [event], []])
            return
        }
        #endif
        let sessions = days > 0 ? repository.fetchRecentSessions(days: days) : []
        
        guard !sessions.isEmpty else {
            resetMetrics()
            return
        }
        
        totalSessions = sessions.count
        
        var onTimeSessions = 0
        var completedCount = 0
        var skippedCount = 0
        var totalInterval: Double = 0
        var intervalsCount = 0
        var wakeMethods: [Dose2WakeKind] = []
        var nightEvents: [[StoredSleepEvent]] = []
        
        var insights: [SessionInsight] = []
        
        for session in sessions {
            var intervalMinutes: Int? = nil
            var isOnTime = false
            let doseLog = repository.fetchDoseLog(forSession: session.sessionDate)
            let doseEvents = repository.fetchDoseEvents(forSessionDate: session.sessionDate)
            let derivedDose = deriveDoseMetrics(from: doseEvents)
            let resolvedDose1 = session.dose1Time ?? doseLog?.dose1Time ?? derivedDose.dose1Time
            let resolvedDose2 = session.dose2Time ?? doseLog?.dose2Time ?? derivedDose.dose2Time
            let resolvedDose2Skipped = session.dose2Skipped || doseLog?.dose2Skipped == true || derivedDose.dose2Skipped
            let resolvedSnoozeCount = max(session.snoozeCount, doseLog?.snoozeCount ?? 0)
            
            // Calculate interval if both doses taken
            if let d1 = resolvedDose1, let d2 = resolvedDose2 {
                let minutes = TimeIntervalMath.minutesBetween(start: d1, end: d2)
                intervalMinutes = minutes
                totalInterval += Double(minutes)
                intervalsCount += 1
                
                // On-time if within 150-240 minute window
                isOnTime = MedicationTiming.classify(dose1: d1, dose2: d2) == .inWindow
                if isOnTime {
                    onTimeSessions += 1
                }
                
                completedCount += 1
                
                if let diary = try? repository.nightOutcomeSnapshot(sessionDate: session.sessionDate),
                   diary.history.events.contains(where: { $0.eventType == "dose2" }) {
                    wakeMethods.append(diary.record?.answers.wakeMethod ?? .unknown)
                }
            }
            
            if resolvedDose2Skipped {
                skippedCount += 1
            }
            
            let events = repository.fetchSleepEvents(forSession: session.sessionDate)
            nightEvents.append(events)
            let bathroomCount = BathroomLogSummary(nightEvents: [events]).totalLogs
            
            let insight = SessionInsight(
                sessionDate: session.sessionDate,
                dose1Time: resolvedDose1,
                dose2Time: resolvedDose2,
                intervalMinutes: intervalMinutes,
                isOnTime: isOnTime,
                isSkipped: resolvedDose2Skipped,
                snoozeCount: resolvedSnoozeCount,
                eventCount: session.eventCount,
                bathroomLogCount: bathroomCount
            )
            insights.append(insight)
        }
        
        // Calculate percentages and averages
        completedSessions = completedCount
        skippedSessions = skippedCount
        onTimeSessionCount = onTimeSessions
        intervalSampleCount = intervalsCount
        bathroomLogs = BathroomLogSummary(nightEvents: nightEvents)
        let wakeSummary = WakeMethodSummary(wakeMethods)
        wakeMethodSampleCount = wakeSummary.answeredCount
        naturalWakePercentage = wakeSummary.naturalPercentage ?? 0
        
        if completedCount > 0 {
            onTimePercentage = Double(onTimeSessions) / Double(completedCount) * 100
        } else {
            onTimePercentage = 0
            naturalWakePercentage = 0
        }
        
        if intervalsCount > 0 {
            averageIntervalMinutes = totalInterval / Double(intervalsCount)
        } else {
            averageIntervalMinutes = 0
        }
        
        recentSessions = insights
    }
    
    /// Reset all metrics to zero
    private func resetMetrics() {
        onTimePercentage = 0
        averageIntervalMinutes = 0
        naturalWakePercentage = 0
        wakeMethodSampleCount = 0
        bathroomLogs = BathroomLogSummary(nightEvents: [])
        totalSessions = 0
        completedSessions = 0
        skippedSessions = 0
        onTimeSessionCount = 0
        intervalSampleCount = 0
        recentSessions = []
    }
    
    // MARK: - Formatted Values
    
    var formattedOnTimePercentage: String {
        guard completedSessions > 0 else { return "No data yet" }
        return String(format: "%.0f%%", onTimePercentage)
    }
    
    var formattedAverageInterval: String {
        guard intervalSampleCount > 0 else { return "No data yet" }
        let hours = Int(averageIntervalMinutes) / 60
        let mins = Int(averageIntervalMinutes) % 60
        return "\(hours)h \(mins)m"
    }
    
    var formattedNaturalWakePercentage: String {
        guard wakeMethodSampleCount > 0 else { return "No data yet" }
        return String(format: "%.0f%%", naturalWakePercentage)
    }
    
    var onTimeSummary: String {
        guard completedSessions > 0 else {
            return "Needs at least one completed night"
        }
        return "\(onTimeSessionCount)/\(completedSessions) nights in 150-240m window"
    }

    var intervalSummary: String {
        if intervalSampleCount == 0 {
            return "Needs dose 1 and dose 2 on the same night"
        }
        if intervalSampleCount < 3 {
            return "Early trend (\(intervalSampleCount)/3 nights)"
        }
        return "Based on \(intervalSampleCount) completed nights"
    }

    var naturalWakeSummary: String {
        guard wakeMethodSampleCount > 0 else {
            return "Record how you woke for Dose 2; snoozes do not identify wake method"
        }
        return "\(wakeMethodSampleCount) explicitly answered Dose 2 wakes; unknown answers excluded"
    }

    var completionRate: String {
        guard totalSessions > 0 else { return "–" }
        let rate = Double(completedSessions) / Double(totalSessions) * 100
        return String(format: "%.0f%%", rate)
    }
}

// MARK: - Insights Summary Card View

struct InsightsSummaryCard: View {
    @ObservedObject var insights = InsightsCalculator.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var title: String = "Your Insights"
    var showDefinitions: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("Recorded nights: \(insights.totalSessions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : (showDefinitions ? 2 : 4)),
                      alignment: .center, spacing: 8) {
                InsightMetricView(
                    title: "On-Time",
                    value: insights.formattedOnTimePercentage,
                    icon: "checkmark.circle.fill",
                    color: insights.completedSessions == 0 ? .gray : (insights.onTimePercentage >= 80 ? .green : (insights.onTimePercentage >= 50 ? .orange : .red)),
                    detail: insights.onTimeSummary,
                    showDetail: showDefinitions
                )
                
                InsightMetricView(
                    title: "Avg Interval",
                    value: insights.formattedAverageInterval,
                    icon: "clock.fill",
                    color: insights.intervalSampleCount == 0 ? .gray : .blue,
                    detail: insights.intervalSummary,
                    showDetail: showDefinitions
                )
                InsightMetricView(
                    title: "Natural Wake",
                    value: insights.formattedNaturalWakePercentage,
                    icon: "sun.max.fill",
                    color: insights.wakeMethodSampleCount == 0 ? .gray : .yellow,
                    detail: insights.naturalWakeSummary,
                    showDetail: showDefinitions
                )
                
                InsightMetricView(
                    title: "Bathroom Logs",
                    value: insights.bathroomLogs.valueText,
                    icon: "list.bullet",
                    color: insights.bathroomLogs.totalLogs == 0 ? .gray : .purple,
                    detail: insights.bathroomLogs.explanation,
                    showDetail: false
                )
            }
            Text(insights.bathroomLogs.explanation)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .onAppear {
            insights.computeInsights()
        }
        .onReceive(SessionRepository.shared.sessionDidChange) { _ in
            insights.computeInsights()
        }
    }
}

struct InsightMetricView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    let icon: String
    let color: Color
    let detail: String?
    let showDetail: Bool
    
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if showDetail, let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail ?? "")")
        .accessibilityIdentifier("insight-\(title)")
    }
}
