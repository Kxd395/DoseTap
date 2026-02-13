import Foundation
import SwiftUI
import DoseCore

/// Calculates insights metrics from historical session data
/// Metrics: on-time %, average interval, natural wake %, WASO, session count
@MainActor
public class InsightsCalculator: ObservableObject {
    
    static let shared = InsightsCalculator()
    
    // MARK: - Published Metrics
    @Published var onTimePercentage: Double = 0
    @Published var averageIntervalMinutes: Double = 0
    @Published var naturalWakePercentage: Double = 0
    @Published var averageWASO: TimeInterval = 0  // Wake After Sleep Onset (in minutes)
    @Published var totalSessions: Int = 0
    @Published var completedSessions: Int = 0
    @Published var skippedSessions: Int = 0
    @Published var onTimeSessionCount: Int = 0
    @Published var intervalSampleCount: Int = 0
    @Published var bathroomWakeSampleCount: Int = 0
    
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
        let wasoMinutes: Int  // Estimated WASO from bathroom events
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
        let sessions = SessionRepository.shared.fetchRecentSessions(days: days)
        
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
        var naturalWakes = 0
        var totalWASO: TimeInterval = 0
        var wasoCount = 0
        
        var insights: [SessionInsight] = []
        
        for session in sessions {
            var intervalMinutes: Int? = nil
            var isOnTime = false
            var wasoMinutes = 0
            let doseLog = SessionRepository.shared.fetchDoseLog(forSession: session.sessionDate)
            let doseEvents = SessionRepository.shared.fetchDoseEvents(forSessionDate: session.sessionDate)
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
                isOnTime = minutes >= 150 && minutes <= 240
                if isOnTime {
                    onTimeSessions += 1
                }
                
                completedCount += 1
                
                // Natural wake detection: no snoozes used = likely natural wake
                if resolvedSnoozeCount == 0 {
                    naturalWakes += 1
                }
            }
            
            if resolvedDose2Skipped {
                skippedCount += 1
            }
            
            // Estimate WASO from bathroom events during the session
            let events = SessionRepository.shared.fetchSleepEvents(forSession: session.sessionDate)
            let bathroomEvents = events.filter { $0.eventType == "bathroom" || $0.eventType == "Bathroom" }
            
            // Assume each bathroom event = ~5 min wake time
            wasoMinutes = bathroomEvents.count * 5
            if wasoMinutes > 0 {
                totalWASO += TimeInterval(wasoMinutes)
                wasoCount += 1
            }
            
            let insight = SessionInsight(
                sessionDate: session.sessionDate,
                dose1Time: resolvedDose1,
                dose2Time: resolvedDose2,
                intervalMinutes: intervalMinutes,
                isOnTime: isOnTime,
                isSkipped: resolvedDose2Skipped,
                snoozeCount: resolvedSnoozeCount,
                eventCount: session.eventCount,
                wasoMinutes: wasoMinutes
            )
            insights.append(insight)
        }
        
        // Calculate percentages and averages
        completedSessions = completedCount
        skippedSessions = skippedCount
        onTimeSessionCount = onTimeSessions
        intervalSampleCount = intervalsCount
        bathroomWakeSampleCount = wasoCount
        
        if completedCount > 0 {
            onTimePercentage = Double(onTimeSessions) / Double(completedCount) * 100
            naturalWakePercentage = Double(naturalWakes) / Double(completedCount) * 100
        } else {
            onTimePercentage = 0
            naturalWakePercentage = 0
        }
        
        if intervalsCount > 0 {
            averageIntervalMinutes = totalInterval / Double(intervalsCount)
        } else {
            averageIntervalMinutes = 0
        }
        
        if wasoCount > 0 {
            averageWASO = totalWASO / Double(wasoCount)
        } else {
            averageWASO = 0
        }
        
        recentSessions = insights
    }
    
    /// Reset all metrics to zero
    private func resetMetrics() {
        onTimePercentage = 0
        averageIntervalMinutes = 0
        naturalWakePercentage = 0
        averageWASO = 0
        totalSessions = 0
        completedSessions = 0
        skippedSessions = 0
        onTimeSessionCount = 0
        intervalSampleCount = 0
        bathroomWakeSampleCount = 0
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
        guard completedSessions > 0 else { return "No data yet" }
        return String(format: "%.0f%%", naturalWakePercentage)
    }
    
    var formattedAverageWASO: String {
        guard bathroomWakeSampleCount > 0 else { return "No data yet" }
        return String(format: "%.0f min", averageWASO)
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
        guard completedSessions > 0 else {
            return "Natural wake = no snoozes used"
        }
        return "\(completedSessions) completed nights analyzed"
    }

    var bathroomWakeSummary: String {
        guard bathroomWakeSampleCount > 0 else {
            return "Estimated from bathroom logs only"
        }
        return "Estimated at 5 min per bathroom event"
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
    var title: String = "Your Insights"
    var showDefinitions: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("Last \(insights.totalSessions) nights")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
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
            }

            HStack(spacing: 12) {
                InsightMetricView(
                    title: "Natural Wake",
                    value: insights.formattedNaturalWakePercentage,
                    icon: "sun.max.fill",
                    color: insights.completedSessions == 0 ? .gray : .yellow,
                    detail: insights.naturalWakeSummary,
                    showDetail: showDefinitions
                )
                
                InsightMetricView(
                    title: "Avg Bathroom Wake",
                    value: insights.formattedAverageWASO,
                    icon: "moon.zzz.fill",
                    color: insights.bathroomWakeSampleCount == 0 ? .gray : .purple,
                    detail: insights.bathroomWakeSummary,
                    showDetail: showDefinitions
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .onAppear {
            insights.computeInsights()
        }
    }
}

struct InsightMetricView: View {
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)

            if showDetail, let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
