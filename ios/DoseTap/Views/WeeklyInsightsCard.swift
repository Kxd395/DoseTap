//
//  WeeklyInsightsCard.swift
//  DoseTap
//
//  Shows a compact 7-day adherence summary on the Tonight tab.
//  Purely derived from SessionRepository — no new storage.
//

import SwiftUI

struct WeeklyInsightsCard: View {
    @ObservedObject var sessionRepo: SessionRepository
    @State private var sessions: [SessionSummary] = []

    /// The current session's date, excluded from "completed/skipped" counts
    /// so tonight doesn't prematurely count as incomplete.
    private var activeSessionDate: String {
        sessionRepo.currentSessionDateString()
    }

    private var pastSessions: [SessionSummary] {
        sessions.filter { $0.sessionDate != activeSessionDate }
    }

    private var completedCount: Int {
        pastSessions.filter { $0.dose2Time != nil && !$0.dose2Skipped }.count
    }

    private var skippedCount: Int {
        pastSessions.filter { $0.dose2Skipped }.count
    }

    private var trackedCount: Int {
        pastSessions.filter { $0.dose1Time != nil }.count
    }

    /// Completed / tracked, nil if nothing tracked yet.
    private var adherenceRate: Double? {
        guard trackedCount > 0 else { return nil }
        return Double(completedCount) / Double(trackedCount)
    }

    /// Average interval in minutes (Dose 1 → Dose 2) across completed sessions.
    private var averageInterval: Int? {
        let intervals = pastSessions.compactMap { $0.intervalMinutes }
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / intervals.count
    }

    /// Longest consecutive completed streak (most-recent contiguous run).
    private var currentStreak: Int {
        let ordered = pastSessions.sorted { $0.sessionDate > $1.sessionDate }
        var streak = 0
        for s in ordered {
            if s.dose2Time != nil && !s.dose2Skipped {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Text("This Week")
                    .font(.headline)
                Spacer()
                if trackedCount > 0 {
                    Text("\(trackedCount)/7 tracked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if pastSessions.isEmpty {
                emptyState
            } else {
                statsGrid
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .onAppear(perform: reload)
        .onReceive(sessionRepo.sessionDidChange) { _ in reload() }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(.secondary)
            Text("Complete a session to see weekly trends")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var statsGrid: some View {
        HStack(spacing: 12) {
            statTile(
                value: adherenceText,
                label: "Adherence",
                color: adherenceColor,
                icon: "checkmark.seal.fill"
            )
            statTile(
                value: averageInterval.map { "\($0)m" } ?? "—",
                label: "Avg interval",
                color: .blue,
                icon: "timer"
            )
            statTile(
                value: "\(currentStreak)",
                label: currentStreak == 1 ? "Day streak" : "Day streak",
                color: currentStreak >= 3 ? .orange : .secondary,
                icon: "flame.fill"
            )
        }

        if skippedCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("\(skippedCount) skipped this week")
                    .font(.caption2)
                Spacer()
            }
            .foregroundColor(.secondary)
        }
    }

    private func statTile(value: String, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(value)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground).opacity(0.5))
        )
    }

    private var adherenceText: String {
        guard let rate = adherenceRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var adherenceColor: Color {
        guard let rate = adherenceRate else { return .secondary }
        if rate >= 0.85 { return .green }
        if rate >= 0.6 { return .orange }
        return .red
    }

    private var accessibilitySummary: String {
        guard trackedCount > 0 else {
            return "This week: no sessions tracked yet"
        }
        var parts: [String] = []
        parts.append("\(trackedCount) of 7 nights tracked")
        if let rate = adherenceRate {
            parts.append("\(Int((rate * 100).rounded())) percent adherence")
        }
        if let avg = averageInterval {
            parts.append("average interval \(avg) minutes")
        }
        if currentStreak > 0 {
            parts.append("\(currentStreak) day streak")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        return "This week. " + parts.joined(separator: ", ")
    }

    private func reload() {
        sessions = sessionRepo.fetchRecentSessions(days: 7)
    }
}
