import SwiftUI
import DoseCore

// MARK: - History Filter Chips
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case onTime = "On Time"
    case late = "Late"
    case skipped = "Skipped"
    case dose1Only = "D1 Only"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .onTime: return "checkmark.circle.fill"
        case .late: return "clock.badge.exclamationmark"
        case .skipped: return "forward.fill"
        case .dose1Only: return "1.circle"
        }
    }

    func matches(_ session: SessionSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .onTime:
            guard let interval = session.intervalMinutes else { return false }
            return (150...165).contains(interval)
        case .late:
            guard let interval = session.intervalMinutes else { return false }
            return interval > 165 && interval <= 240
        case .skipped:
            return session.dose2Skipped
        case .dose1Only:
            return session.dose1Time != nil && session.dose2Time == nil && !session.dose2Skipped
        }
    }
}

struct HistoryView: View {
    @Environment(\.isInSplitView) private var isInSplitView
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDate = Date()
    @State private var pastSessions: [SessionSummary] = []
    @State private var showDeleteDayConfirmation = false
    @State private var refreshTrigger = false
    @State private var searchText = ""
    @State private var activeFilter: HistoryFilter = .all

    private let sessionRepo = SessionRepository.shared

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    private var isSearchActive: Bool {
        !searchText.isEmpty || activeFilter != .all
    }

    private var filteredSessions: [SessionSummary] {
        var result = pastSessions
        if activeFilter != .all {
            result = result.filter { activeFilter.matches($0) }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { session in
                if session.sessionDate.lowercased().contains(query) { return true }
                if session.sleepEvents.contains(where: {
                    $0.eventType.lowercased().contains(query)
                    || ($0.notes?.lowercased().contains(query) ?? false)
                }) { return true }
                if let interval = session.intervalMinutes, "\(interval)m".contains(query) { return true }
                if session.dose2Skipped && "skipped".contains(query) { return true }
                return false
            }
        }
        return result
    }

    var body: some View {
        if isInSplitView {
            historyContent
        } else {
            NavigationView {
                historyContent
            }
        }
    }

    private var historyContent: some View {
        ScrollView {
            historyFilterBar

            if isSearchActive {
                filteredResultsList
            } else if isWideLayout {
                wideHistoryLayout
            } else {
                compactHistoryLayout
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search sessions, events…")
        .onChange(of: searchText) { _ in
            if isSearchActive {
                ensureExpandedHistory()
            }
        }
        .refreshable {
            loadHistory()
        }
        .onAppear { loadHistory() }
        .alert("Delete This Day's Data?", isPresented: $showDeleteDayConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedDay()
            }
        } message: {
            Text("This will delete all dose data and events for this day. This cannot be undone.")
        }
    }

    private var historyFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if activeFilter == filter {
                                activeFilter = .all
                            } else {
                                activeFilter = filter
                                if filter != .all {
                                    ensureExpandedHistory()
                                }
                            }
                        }
                    } label: {
                        Label(filter.rawValue, systemImage: filter.icon)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(activeFilter == filter ? Color.accentColor : Color(.systemGray5))
                            )
                            .foregroundColor(activeFilter == filter ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private var filteredResultsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(filteredSessions.count) result\(filteredSessions.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No matching sessions")
                        .font(.headline)
                    Text("Try a different search term or filter.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSessions, id: \.sessionDate) { session in
                        SessionSearchResultRow(session: session)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 80)
    }

    private var wideHistoryLayout: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trends")
                    .font(.headline)
                InsightsSummaryCard()
            }
            .padding(.horizontal)

            HStack(alignment: .top, spacing: 16) {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    SelectedDayView(
                        date: selectedDate,
                        refreshTrigger: refreshTrigger,
                        onDeleteRequested: { showDeleteDayConfirmation = true }
                    )
                    RecentSessionsList()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            NavigationLink {
                NightComparisonPickerView()
            } label: {
                Label("Compare Nights", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .padding(.bottom, 80)
    }

    private var compactHistoryLayout: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trends")
                    .font(.headline)
                InsightsSummaryCard()
            }

            DatePicker(
                "Select Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )

            SelectedDayView(
                date: selectedDate,
                refreshTrigger: refreshTrigger,
                onDeleteRequested: { showDeleteDayConfirmation = true }
            )

            RecentSessionsList()

            NavigationLink {
                NightComparisonPickerView()
            } label: {
                Label("Compare Nights", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .padding(.bottom, 80)
    }

    private func loadHistory() {
        pastSessions = sessionRepo.fetchRecentSessions(days: 30)
    }

    private func ensureExpandedHistory() {
        guard pastSessions.count < 90 else { return }
        pastSessions = sessionRepo.fetchRecentSessions(days: 90)
    }

    private func deleteSelectedDay() {
        let sessionDate = sessionRepo.sessionDateString(for: eveningAnchorDate(for: selectedDate))
        sessionRepo.deleteSession(sessionDate: sessionDate)
        refreshTrigger.toggle()
        loadHistory()
    }
}

#Preview {
    let container = AppContainer()
    return ContentView()
        .environmentObject(container)
        .environmentObject(container.settings)
        .environmentObject(container.sessionRepository)
        .environmentObject(container.alarmService)
}
