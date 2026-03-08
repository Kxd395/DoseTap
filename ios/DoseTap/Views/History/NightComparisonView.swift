// NightComparisonView.swift — P3-6 Side-by-side night comparison
import SwiftUI
import DoseCore

/// Compare two nights' metrics side-by-side.
/// Navigate here from History (long-press a session) or Dashboard.
struct NightComparisonView: View {
    let leftSession: SessionSummary
    let rightSession: SessionSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerRow
                doseTimingSection
                intervalSection
                eventsSection
            }
            .padding()
        }
        .navigationTitle("Compare Nights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header
    private var headerRow: some View {
        HStack {
            dateColumn(leftSession.sessionDate, alignment: .leading)
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.title3)
                .foregroundColor(.secondary)
            Spacer()
            dateColumn(rightSession.sessionDate, alignment: .trailing)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    private func dateColumn(_ date: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(date)
                .font(.headline)
            Text(statusLabel(for: sessionByDate(date)))
                .font(.caption)
                .foregroundColor(statusColor(for: sessionByDate(date)))
        }
    }

    // MARK: - Dose Timing
    private var doseTimingSection: some View {
        comparisonCard(title: "Dose Timing", icon: "pills.fill") {
            comparisonRow(label: "Dose 1",
                          left: leftSession.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "—",
                          right: rightSession.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "—")
            comparisonRow(label: "Dose 2",
                          left: dose2Text(leftSession),
                          right: dose2Text(rightSession))
            comparisonRow(label: "Snoozes",
                          left: "\(leftSession.snoozeCount)",
                          right: "\(rightSession.snoozeCount)")
        }
    }

    // MARK: - Interval
    private var intervalSection: some View {
        comparisonCard(title: "Interval", icon: "timer") {
            comparisonRow(
                label: "Minutes",
                left: leftSession.intervalMinutes.map { "\($0)m" } ?? "—",
                right: rightSession.intervalMinutes.map { "\($0)m" } ?? "—"
            )
            comparisonRow(
                label: "Zone",
                left: zoneName(leftSession),
                right: zoneName(rightSession)
            )
        }
    }

    // MARK: - Events
    private var eventsSection: some View {
        comparisonCard(title: "Events", icon: "list.bullet") {
            comparisonRow(
                label: "Total",
                left: "\(leftSession.eventCount)",
                right: "\(rightSession.eventCount)"
            )

            let leftTypes = Set(leftSession.sleepEvents.map(\.eventType))
            let rightTypes = Set(rightSession.sleepEvents.map(\.eventType))
            let allTypes = leftTypes.union(rightTypes).sorted()

            ForEach(allTypes, id: \.self) { eventType in
                let lCount = leftSession.sleepEvents.filter { $0.eventType == eventType }.count
                let rCount = rightSession.sleepEvents.filter { $0.eventType == eventType }.count
                comparisonRow(
                    label: eventType,
                    left: lCount > 0 ? "\(lCount)" : "—",
                    right: rCount > 0 ? "\(rCount)" : "—"
                )
            }
        }
    }

    // MARK: - Reusable components

    private func comparisonCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    private func comparisonRow(label: String, left: String, right: String) -> some View {
        HStack {
            Text(left)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 80)
            Text(right)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func sessionByDate(_ date: String) -> SessionSummary {
        date == leftSession.sessionDate ? leftSession : rightSession
    }

    private func dose2Text(_ s: SessionSummary) -> String {
        if let t = s.dose2Time { return t.formatted(date: .omitted, time: .shortened) }
        if s.dose2Skipped { return "Skipped" }
        return "—"
    }

    private func zoneName(_ s: SessionSummary) -> String {
        guard let iv = s.intervalMinutes else {
            return s.dose2Skipped ? "Skipped" : "—"
        }
        if (150...165).contains(iv) { return "Optimal" }
        if iv > 165 && iv <= 240 { return "Acceptable" }
        return "Out of window"
    }

    private func statusLabel(for s: SessionSummary) -> String {
        if s.dose2Skipped { return "Skipped" }
        guard let iv = s.intervalMinutes else { return "Incomplete" }
        if (150...165).contains(iv) { return "On Time" }
        if iv > 165 && iv <= 240 { return "Late" }
        return "Out of Window"
    }

    private func statusColor(for s: SessionSummary) -> Color {
        if s.dose2Skipped { return .orange }
        guard let iv = s.intervalMinutes else { return .secondary }
        if (150...165).contains(iv) { return .green }
        if iv > 165 && iv <= 240 { return .yellow }
        return .red
    }
}

// MARK: - Night Picker (select two nights for comparison)
struct NightComparisonPickerView: View {
    @State private var sessions: [SessionSummary] = []
    @State private var leftIndex: Int = 0
    @State private var rightIndex: Int = 1

    var body: some View {
        VStack(spacing: 16) {
            if sessions.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Need at least 2 sessions to compare")
                        .font(.headline)
                    Text("Log more nights and come back.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 60)
            } else {
                Picker("Night A", selection: $leftIndex) {
                    ForEach(sessions.indices, id: \.self) { i in
                        Text(sessions[i].sessionDate).tag(i)
                    }
                }

                Picker("Night B", selection: $rightIndex) {
                    ForEach(sessions.indices, id: \.self) { i in
                        Text(sessions[i].sessionDate).tag(i)
                    }
                }

                if leftIndex != rightIndex {
                    NavigationLink("Compare") {
                        NightComparisonView(
                            leftSession: sessions[leftIndex],
                            rightSession: sessions[rightIndex]
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Select two different nights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .navigationTitle("Compare Nights")
        .onAppear {
            sessions = SessionRepository.shared.fetchRecentSessions(days: 90)
            if sessions.count >= 2 { rightIndex = 1 }
        }
    }
}
