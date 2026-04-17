import SwiftUI

struct LibraryView: View {
    @ObservedObject var dataStore: DataStore
    @State private var filters = InsightFilterState()
    @State private var selectedSessionID: InsightSession.ID?

    private var filteredSessions: [InsightSession] {
        dataStore.insightSessions.filter { $0.matches(filters: filters) }
    }

    private var selectedSession: InsightSession? {
        if let selectedSessionID {
            return filteredSessions.first(where: { $0.id == selectedSessionID })
        }
        return filteredSessions.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Night Library")
                    .font(.largeTitle.bold())

                validationSummary
                filterBar
                summaryRow

                if filteredSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No nights match these filters")
                            .font(.headline)
                        Text("Adjust filters or import more exported data.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(filteredSessions, selection: $selectedSessionID) {
                        TableColumn("Night") { session in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.sessionDate)
                                HStack(spacing: 6) {
                                    InsightBadge(
                                        text: session.classification.confidenceBucket.label,
                                        tint: insightConfidenceColor(for: session.classification.confidenceBucket)
                                    )
                                    if session.countsTowardRecommendationTraining {
                                        InsightBadge(text: "Trainable", tint: .green)
                                    }
                                }
                            }
                        }
                        TableColumn("Dose 1") { session in
                            Text(timeText(for: session.dose1Time))
                        }
                        TableColumn("Dose 2") { session in
                            Text(session.dose2Skipped ? "Skipped" : timeText(for: session.dose2Time))
                        }
                        TableColumn("Interval") { session in
                            Text(session.intervalMinutes.map { "\($0)m" } ?? "—")
                        }
                        TableColumn("Events") { session in
                            Text("\(session.eventCount)")
                        }
                        TableColumn("Quality") { session in
                            qualityBadgeRow(for: session)
                        }
                        TableColumn("Night Type") { session in
                            InsightBadge(
                                text: session.nightTypeFilter.rawValue.replacingOccurrences(of: " Nights", with: ""),
                                tint: insightNightTypeColor(for: session)
                            )
                        }
                        TableColumn("Sources") { session in
                            sourceBadgeRow(for: session)
                        }
                    }
                }
            }
            .frame(minWidth: 560)
            .padding()

            if let selectedSession {
                NightDetailView(session: selectedSession)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Select a night")
                        .font(.headline)
                    Text("Night details will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Library")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: filteredSessions.map(\.id)) { _ in
            ensureSelection()
        }
    }

    private var filterBar: some View {
        InsightFilterBar(
            filters: $filters,
            showsSearch: true,
            showsLateDose: true,
            showsSkipped: true,
            showsQualityIssues: true,
            showsTrainable: true
        )
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            libraryCard(title: "Visible Nights", value: "\(filteredSessions.count)", accent: .blue)
            libraryCard(title: "Late Dose 2", value: "\(filteredSessions.filter(\.isLateDose2).count)", accent: .orange)
            libraryCard(title: "Skipped", value: "\(filteredSessions.filter(\.dose2Skipped).count)", accent: .red)
            libraryCard(title: "Quality Issues", value: "\(filteredSessions.filter { !$0.qualityFlags.isEmpty }.count)", accent: .purple)
            if dataStore.validationReport.hasIssues {
                libraryCard(
                    title: "Import Issues",
                    value: "\(dataStore.validationReport.totalIssueCount)",
                    accent: .orange
                )
            }
            Spacer()
        }
    }

    private var validationSummary: some View {
        Group {
            if dataStore.validationReport.hasIssues {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import Warnings Detected")
                                .font(.headline)
                            Text(
                                "\(dataStore.validationReport.totalIssueCount) issue(s) across \(dataStore.validationReport.affectedSessionCount) night(s). Treat trend outputs cautiously until these are reviewed."
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    if !dataStore.validationReport.globalFlags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(dataStore.validationReport.globalFlags, id: \.self) { flag in
                                validationRow(flag)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
    }

    private func libraryCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(accent)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 132, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func validationRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "smallcircle.fill.circle")
                .font(.caption2)
                .foregroundColor(.orange)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func qualityBadgeRow(for session: InsightSession) -> some View {
        InsightQualityBadgeRow(session: session)
    }

    private func sourceBadgeRow(for session: InsightSession) -> some View {
        InsightSourceBadgeRow(session: session)
    }

    private func timeText(for date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func ensureSelection() {
        guard !filteredSessions.isEmpty else {
            selectedSessionID = nil
            return
        }

        if let selectedSessionID,
           filteredSessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        selectedSessionID = filteredSessions.first?.id
    }
}

#Preview {
    LibraryView(dataStore: DataStore())
}
