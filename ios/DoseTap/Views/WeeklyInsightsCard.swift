//
//  WeeklyInsightsCard.swift
//  DoseTap
//
//  Shows a compact 7-day adherence summary on the Tonight tab.
//  Purely derived from SessionRepository — no new storage.
//

import SwiftUI

struct WeeklyRecordedDoseMetrics {
    let sessions: [SessionSummary]

    init(sessions: [SessionSummary], currentNight: String) {
        guard let anchor = AppFormatters.sessionDate.date(from: currentNight),
              let lower = Calendar.current.date(byAdding: .day, value: -7, to: anchor) else {
            self.sessions = []
            return
        }
        self.sessions = sessions.filter {
            guard let date = AppFormatters.sessionDate.date(from: $0.sessionDate) else { return false }
            return date >= lower && date < anchor
        }
    }

    var tracked: Int { sessions.filter { $0.dose1Time != nil }.count }
    var recorded: Int { sessions.filter { $0.dose1Time != nil && $0.dose2Time != nil }.count }
    var skipped: Int { sessions.filter { $0.dose1Time != nil && $0.dose2Time == nil && $0.dose2Skipped }.count }
    var missing: Int { max(0, tracked - recorded - skipped) }
}

struct WeeklyInsightsCard: View {
    @ObservedObject var sessionRepo: SessionRepository
    @State private var sessions: [SessionSummary] = []

    /// The current session's date, excluded from "completed/skipped" counts
    /// so tonight doesn't prematurely count as incomplete.
    private var activeSessionDate: String {
        sessionRepo.currentSessionDateString()
    }

    private var weeklyMetrics: WeeklyRecordedDoseMetrics {
        WeeklyRecordedDoseMetrics(sessions: sessions, currentNight: activeSessionDate)
    }

    private var pastSessions: [SessionSummary] {
        weeklyMetrics.sessions
    }

    private var completedCount: Int {
        weeklyMetrics.recorded
    }

    private var skippedCount: Int {
        weeklyMetrics.skipped
    }

    private var trackedCount: Int {
        weeklyMetrics.tracked
    }

    /// Completed / tracked, nil if nothing tracked yet.
    private var dose2RecordedRate: Double? {
        guard trackedCount > 0 else { return nil }
        return Double(completedCount) / Double(trackedCount)
    }

    /// Average interval in minutes (Dose 1 → Dose 2) across completed sessions.
    private var averageInterval: Int? {
        let intervals = pastSessions.compactMap { session -> Double? in
            guard let first = session.dose1Time, let second = session.dose2Time else { return nil }
            let seconds = second.timeIntervalSince(first)
            return seconds.isFinite && seconds >= 0 ? seconds / 60 : nil
        }
        guard !intervals.isEmpty else { return nil }
        return Int((intervals.reduce(0, +) / Double(intervals.count)).rounded())
    }

    private var missingCount: Int { weeklyMetrics.missing }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Text("Last 7 Nights")
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
                value: dose2RecordedText,
                label: "Dose 2 recorded",
                color: dose2RecordedColor,
                icon: "checkmark.seal.fill"
            )
            statTile(
                value: averageInterval.map { "\($0)m" } ?? "—",
                label: "Avg interval",
                color: .blue,
                icon: "timer"
            )
            statTile(
                value: "\(missingCount)",
                label: "Unrecorded",
                color: missingCount > 0 ? .orange : .secondary,
                icon: "info.circle"
            )
        }

        if skippedCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("\(skippedCount) explicitly skipped")
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

    private var dose2RecordedText: String {
        guard let rate = dose2RecordedRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var dose2RecordedColor: Color {
        guard let rate = dose2RecordedRate else { return .secondary }
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
        if let rate = dose2RecordedRate {
            parts.append("\(Int((rate * 100).rounded())) percent with Dose 2 recorded")
        }
        if let avg = averageInterval {
            parts.append("average interval \(avg) minutes")
        }
        if missingCount > 0 {
            parts.append("\(missingCount) unrecorded outcomes")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        return "Last seven finished nights. " + parts.joined(separator: ", ")
    }

    private func reload() {
        sessions = sessionRepo.fetchRecentSessions(days: 8)
    }
}
