import SwiftUI

struct LibraryView: View {
    @ObservedObject var dataStore: DataStore
    @State private var filters = InsightFilterState()
    @State private var selectedSessionID: InsightSession.ID?

    private var filteredSessions: [InsightSession] {
        dataStore.insightSessions.filter { session in
            matchesFilters(session)
        }
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
                            Text(session.sessionDate)
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
                            Text(session.qualitySummary)
                                .foregroundColor(session.qualityFlags.isEmpty ? .secondary : .orange)
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
        HStack(spacing: 12) {
            TextField("Search date or note", text: $filters.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Toggle("Late Dose 2", isOn: $filters.lateDoseOnly)
                .toggleStyle(.switch)
            Toggle("Skipped", isOn: $filters.skippedOnly)
                .toggleStyle(.switch)
            Toggle("Quality Issues", isOn: $filters.qualityIssuesOnly)
                .toggleStyle(.switch)

            Spacer()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            libraryCard(title: "Visible Nights", value: "\(filteredSessions.count)", accent: .blue)
            libraryCard(title: "Late Dose 2", value: "\(filteredSessions.filter(\.isLateDose2).count)", accent: .orange)
            libraryCard(title: "Skipped", value: "\(filteredSessions.filter(\.dose2Skipped).count)", accent: .red)
            libraryCard(title: "Quality Issues", value: "\(filteredSessions.filter { !$0.qualityFlags.isEmpty }.count)", accent: .purple)
            Spacer()
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

    private func matchesFilters(_ session: InsightSession) -> Bool {
        if filters.lateDoseOnly && !session.isLateDose2 {
            return false
        }
        if filters.skippedOnly && !session.dose2Skipped {
            return false
        }
        if filters.qualityIssuesOnly && session.qualityFlags.isEmpty {
            return false
        }

        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return true
        }

        let haystack = [
            session.sessionDate,
            session.notes ?? "",
            session.qualitySummary,
            session.adherenceFlag ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query.lowercased())
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
