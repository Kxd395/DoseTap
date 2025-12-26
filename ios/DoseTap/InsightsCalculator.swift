import Foundation
import SwiftUI

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
            
            // Calculate interval if both doses taken
            if let d1 = session.dose1Time, let d2 = session.dose2Time {
                let interval = d2.timeIntervalSince(d1) / 60  // minutes
                intervalMinutes = Int(interval)
                totalInterval += interval
                intervalsCount += 1
                
                // On-time if within 150-240 minute window
                isOnTime = interval >= 150 && interval <= 240
                if isOnTime {
                    onTimeSessions += 1
                }
                
                completedCount += 1
                
                // Natural wake detection: no snoozes used = likely natural wake
                if session.snoozeCount == 0 {
                    naturalWakes += 1
                }
            }
            
            if session.dose2Skipped {
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
                dose1Time: session.dose1Time,
                dose2Time: session.dose2Time,
                intervalMinutes: intervalMinutes,
                isOnTime: isOnTime,
                isSkipped: session.dose2Skipped,
                snoozeCount: session.snoozeCount,
                eventCount: session.eventCount,
                wasoMinutes: wasoMinutes
            )
            insights.append(insight)
        }
        
        // Calculate percentages and averages
        completedSessions = completedCount
        skippedSessions = skippedCount
        
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
        recentSessions = []
    }
    
    // MARK: - Formatted Values
    
    var formattedOnTimePercentage: String {
        String(format: "%.0f%%", onTimePercentage)
    }
    
    var formattedAverageInterval: String {
        if averageIntervalMinutes == 0 { return "–" }
        let hours = Int(averageIntervalMinutes) / 60
        let mins = Int(averageIntervalMinutes) % 60
        return "\(hours)h \(mins)m"
    }
    
    var formattedNaturalWakePercentage: String {
        String(format: "%.0f%%", naturalWakePercentage)
    }
    
    var formattedAverageWASO: String {
        if averageWASO == 0 { return "0 min" }
        return String(format: "%.0f min", averageWASO)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Insights")
                    .font(.headline)
                Spacer()
                Text("Last \(insights.totalSessions) nights")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                InsightMetricView(
                    title: "On-Time",
                    value: insights.formattedOnTimePercentage,
                    icon: "checkmark.circle.fill",
                    color: insights.onTimePercentage >= 80 ? .green : (insights.onTimePercentage >= 50 ? .orange : .red)
                )
                
                InsightMetricView(
                    title: "Avg Interval",
                    value: insights.formattedAverageInterval,
                    icon: "clock.fill",
                    color: .blue
                )
                
                InsightMetricView(
                    title: "Natural Wake",
                    value: insights.formattedNaturalWakePercentage,
                    icon: "sun.max.fill",
                    color: .yellow
                )
                
                InsightMetricView(
                    title: "Avg WASO",
                    value: insights.formattedAverageWASO,
                    icon: "moon.zzz.fill",
                    color: .purple
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
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
