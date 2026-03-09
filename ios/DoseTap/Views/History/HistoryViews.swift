import SwiftUI
import DoseCore
#if canImport(UIKit)
import UIKit
#endif

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
        case .all: return true
        case .onTime:
            guard let iv = session.intervalMinutes else { return false }
            return (150...165).contains(iv)
        case .late:
            guard let iv = session.intervalMinutes else { return false }
            return iv > 165 && iv <= 240
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
    @State private var refreshTrigger = false  // Toggled to force SelectedDayView refresh
    @State private var searchText = ""
    @State private var activeFilter: HistoryFilter = .all
    
    private let sessionRepo = SessionRepository.shared

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    /// True when search or filter is active — show filtered results instead of calendar
    private var isSearchActive: Bool {
        !searchText.isEmpty || activeFilter != .all
    }

    private var filteredSessions: [SessionSummary] {
        var result = pastSessions
        // Apply filter chip
        if activeFilter != .all {
            result = result.filter { activeFilter.matches($0) }
        }
        // Apply text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { session in
                if session.sessionDate.lowercased().contains(query) { return true }
                if session.sleepEvents.contains(where: {
                    $0.eventType.lowercased().contains(query)
                    || ($0.notes?.lowercased().contains(query) ?? false)
                }) { return true }
                if let iv = session.intervalMinutes, "\(iv)m".contains(query) { return true }
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
            // Filter chip bar (always visible)
            historyFilterBar

            if isSearchActive {
                // Search / filter results replace calendar
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
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedDay()
            }
        } message: {
            Text("This will delete all dose data and events for this day. This cannot be undone.")
        }
    }

    // MARK: - Filter Chip Bar
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

    // MARK: - Filtered Results List
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

    // MARK: - Wide Layout (iPad)

    private var wideHistoryLayout: some View {
        VStack(spacing: 16) {
            // Trends (full width)
            VStack(alignment: .leading, spacing: 8) {
                Text("Trends")
                    .font(.headline)
                InsightsSummaryCard()
            }
            .padding(.horizontal)

            // Side-by-side: Calendar | Selected Day
            HStack(alignment: .top, spacing: 16) {
                // Left: Calendar picker
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

                // Right: Selected day + recent sessions
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
            
            // P3-6: Compare two nights
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

    // MARK: - Compact Layout (iPhone — unchanged)

    private var compactHistoryLayout: some View {
        VStack(spacing: 16) {
            // Trends
            VStack(alignment: .leading, spacing: 8) {
                Text("Trends")
                    .font(.headline)
                InsightsSummaryCard()
            }
            
            // Date Picker
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
            
            // Selected Day Summary with Delete Option
            SelectedDayView(
                date: selectedDate,
                refreshTrigger: refreshTrigger,
                onDeleteRequested: { showDeleteDayConfirmation = true }
            )
            
            // Recent Sessions List
            RecentSessionsList()
            
            // P3-6: Compare two nights
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
        // Use SessionRepository to delete - this broadcasts change to Tonight tab
        sessionRepo.deleteSession(sessionDate: sessionDate)
        refreshTrigger.toggle()  // Force SelectedDayView to reload
        loadHistory()
    }
}

// MARK: - Selected Day View
struct SelectedDayView: View {
    let date: Date
    var refreshTrigger: Bool = false  // External trigger to force reload
    var onDeleteRequested: (() -> Void)? = nil
    
    @ObservedObject private var settings = UserSettingsManager.shared
    @StateObject private var healthKit = HealthKitService.shared
    @State private var events: [StoredSleepEvent] = []
    @State private var doseLog: StoredDoseLog?
    @State private var doseEvents: [DoseCore.StoredDoseEvent] = []
    @State private var healthSleepRangeText: String?
    @State private var healthSleepStatusText: String?
    @State private var healthSleepSourceText: String?
    @State private var editingDose1 = false
    @State private var editingDose2 = false
    @State private var editingEvent: StoredSleepEvent?
    @State private var eventToDelete: StoredSleepEvent?  // P3-5: swipe/long-press delete
    
    private let sessionRepo = SessionRepository.shared
    
    private var hasData: Bool {
        doseLog != nil || !events.isEmpty
    }

    private struct NapIntervalDisplay: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date?
        let durationMinutes: Int?
    }

    private var napIntervals: [NapIntervalDisplay] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var intervals: [NapIntervalDisplay] = []
        var pendingStart: Date?

        for event in sorted {
            guard let kind = napEventKind(event.eventType) else { continue }
            if kind == "start" {
                pendingStart = event.timestamp
            } else if kind == "end", let start = pendingStart {
                let minutes = TimeIntervalMath.minutesBetween(start: start, end: event.timestamp)
                intervals.append(NapIntervalDisplay(start: start, end: event.timestamp, durationMinutes: minutes))
                pendingStart = nil
            }
        }

        if let start = pendingStart {
            intervals.append(NapIntervalDisplay(start: start, end: nil, durationMinutes: nil))
        }

        return intervals
    }
    
    private var sessionDateString: String {
        sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateTitle)
                    .font(.headline)
                Spacer()
                if hasData {
                    Text("Tap to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if hasData, let onDelete = onDeleteRequested {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health Cross-Check")
                    .font(.subheadline.bold())
                Text("Session key: \(sessionDateString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let healthSleepRangeText {
                    Text("Sleep range: \(healthSleepRangeText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let healthSleepSourceText {
                    Text(healthSleepSourceText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let healthSleepStatusText {
                    Text(healthSleepStatusText)
                        .font(.caption)
                        .foregroundColor(healthSleepStatusText.hasPrefix("Matches") ? .green : .orange)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            
            if let dose = doseLog {
                // Dose info - now tappable
                VStack(alignment: .leading, spacing: 8) {
                    // Dose 1 Row - Tappable
                    Button {
                        editingDose1 = true
                    } label: {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.green)
                            Text("Dose 1")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(dose.dose1Time.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if let d2 = dose.dose2Time {
                        // Dose 2 Row - Tappable
                        Button {
                            editingDose2 = true
                        } label: {
                            HStack {
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(.green)
                                Text("Dose 2")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(d2.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(.secondary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        let interval = TimeIntervalMath.minutesBetween(start: dose.dose1Time, end: d2)
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("Interval")
                            Spacer()
                            Text(TimeIntervalMath.formatMinutes(interval))
                                .foregroundColor(.secondary)
                        }
                    } else if dose.skipped {
                        HStack {
                            Image(systemName: "2.circle")
                                .foregroundColor(.orange)
                            Text("Dose 2")
                            Spacer()
                            Text("Skipped")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }

            if doseLog != nil {
                DoseIntervalsCard(doseEvents: doseEvents)
            }
            
            // Events for this day - now tappable
            if !events.isEmpty {
                Text("Events (\(events.count))")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                
                ForEach(events, id: \.id) { event in
                    Button {
                        editingEvent = event
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(EventDisplayName.displayName(for: event.eventType))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    // P3-5: Long-press context menu with delete
                    .contextMenu {
                        Button {
                            editingEvent = event
                        } label: {
                            Label("Edit Time", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            eventToDelete = event
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    }
                }
            } else {
                Text("No events logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !napIntervals.isEmpty {
                Text("Naps")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                ForEach(napIntervals) { nap in
                    HStack(spacing: 10) {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(napLabel(for: nap))
                                .font(.subheadline)
                            Text(napDetail(for: nap))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onChange(of: date) { _ in loadData() }
        .onChange(of: refreshTrigger) { _ in loadData() }
        .onAppear { loadData() }
        // Edit Dose 1 Sheet
        .sheet(isPresented: $editingDose1) {
            if let dose = doseLog {
                EditDoseTimeView(
                    doseNumber: 1,
                    originalTime: dose.dose1Time,
                    dose1Time: nil,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose1Time(newTime)
                    }
                )
            }
        }
        // Edit Dose 2 Sheet
        .sheet(isPresented: $editingDose2) {
            if let dose = doseLog, let d2 = dose.dose2Time {
                EditDoseTimeView(
                    doseNumber: 2,
                    originalTime: d2,
                    dose1Time: dose.dose1Time,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose2Time(newTime)
                    }
                )
            }
        }
        // Edit Event Sheet
        .sheet(item: $editingEvent) { event in
            EditEventTimeView(
                event: event,
                sessionDate: sessionDateString,
                onSave: { newTime in
                    saveEventTime(event: event, newTime: newTime)
                }
            )
        }
        // P3-5: Delete event confirmation
        .alert("Delete Event?", isPresented: Binding<Bool>(
            get: { eventToDelete != nil },
            set: { if !$0 { eventToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { eventToDelete = nil }
            Button("Delete", role: .destructive) {
                if let event = eventToDelete {
                    sessionRepo.deleteSleepEvent(id: event.id)
                    loadData()
                }
                eventToDelete = nil
            }
        } message: {
            if let event = eventToDelete {
                Text("Delete \"\(EventDisplayName.displayName(for: event.eventType))\" at \(event.timestamp.formatted(date: .omitted, time: .shortened))?")
            }
        }
    }
    
    private var dateTitle: String {
        return AppFormatters.weekdayMedium.string(from: eveningAnchorDate(for: date))
    }
    
    private func loadData() {
        let sessionDate = sessionDateString
        events = sessionRepo.fetchSleepEvents(for: sessionDate)
        doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
        doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
        loadHealthCrossCheck(for: sessionDate)
    }
    
    private func saveDose1Time(_ newTime: Date) {
        sessionRepo.updateDose1Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }
    
    private func saveDose2Time(_ newTime: Date) {
        sessionRepo.updateDose2Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }
    
    private func saveEventTime(event: StoredSleepEvent, newTime: Date) {
        sessionRepo.updateEventTime(eventId: event.id, newTime: newTime)
        loadData()
    }

    private func loadHealthCrossCheck(for sessionDate: String) {
        healthSleepRangeText = nil
        healthSleepSourceText = nil
        healthSleepStatusText = nil

        Task { @MainActor in
            guard settings.healthKitEnabled else {
                healthSleepStatusText = "Apple Health disabled in Settings."
                return
            }

            healthKit.checkAuthorizationStatus()
            guard healthKit.isAuthorized else {
                healthSleepStatusText = "Apple Health not authorized."
                return
            }

            guard let nightDate = AppFormatters.sessionDate.date(from: sessionDate) else {
                healthSleepStatusText = "Unable to parse session date."
                return
            }

            let queryStart = eveningAnchorDate(for: nightDate, hour: 18)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else {
                healthSleepStatusText = "Unable to compute Apple Health query window."
                return
            }
            let queryEnd = eveningAnchorDate(for: nextDay, hour: 12)

            do {
                let segments = try await healthKit.fetchSegmentsForTimeline(from: queryStart, to: queryEnd)
                guard !segments.isEmpty else {
                    healthSleepStatusText = "No Apple Health sleep samples in this night window."
                    return
                }

                let start = segments.map(\.start).min() ?? queryStart
                let end = segments.map(\.end).max() ?? queryEnd

                let formatter = AppFormatters.mediumDateTime
                healthSleepRangeText = "\(formatter.string(from: start)) -> \(formatter.string(from: end))"

                let sourceNames = Set(segments.map(\.source)).sorted()
                if !sourceNames.isEmpty {
                    healthSleepSourceText = "Source: \(sourceNames.joined(separator: ", "))"
                }

                let derivedKey = sessionRepo.sessionDateString(for: start)
                healthSleepStatusText = derivedKey == sessionDate
                    ? "Matches: Health sleep start maps to session \(derivedKey)."
                    : "Mismatch: Health sleep start maps to \(derivedKey), session is \(sessionDate)."
            } catch {
                healthSleepStatusText = "Apple Health error: \(error.localizedDescription)"
            }
        }
    }

    private func napEventKind(_ eventType: String) -> String? {
        let normalized = eventType
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if normalized == "nap start" || compact == "napstart" { return "start" }
        if normalized == "nap end" || compact == "napend" { return "end" }
        return nil
    }

    private func napLabel(for nap: NapIntervalDisplay) -> String {
        if nap.end == nil {
            return "Nap in progress"
        }
        return "Nap"
    }

    private func napDetail(for nap: NapIntervalDisplay) -> String {
        let start = nap.start.formatted(date: .omitted, time: .shortened)
        if let end = nap.end {
            let endStr = end.formatted(date: .omitted, time: .shortened)
            let duration = nap.durationMinutes.map { TimeIntervalMath.formatMinutes($0) } ?? "—"
            return "\(start) -> \(endStr) (\(duration))"
        }
        return "Started at \(start) (no end logged)"
    }
}

// MARK: - Recent Sessions List
struct RecentSessionsList: View {
    @State private var sessions: [SessionSummary] = []
    private let sessionRepo = SessionRepository.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
            
            if sessions.isEmpty {
                Text("No recent sessions found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(sessions, id: \.sessionDate) { session in
                    SessionRow(session: session)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onAppear { loadSessions() }
    }
    
    private func loadSessions() {
        sessions = sessionRepo.fetchRecentSessions(days: 7)
    }
}

struct SessionRow: View {
    let session: SessionSummary
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionDate)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if session.dose1Time != nil {
                        Label("D1", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if session.dose2Time != nil {
                        Label("D2", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if session.skipped {
                        Label("Skipped", systemImage: "forward.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if session.eventCount > 0 {
                        Label("\(session.eventCount)", systemImage: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            Spacer()
            if let d1 = session.dose1Time, let d2 = session.dose2Time {
                let interval = TimeIntervalMath.minutesBetween(start: d1, end: d2)
                Text(TimeIntervalMath.formatMinutes(interval))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Session Search Result Row (richer than SessionRow)
struct SessionSearchResultRow: View {
    let session: SessionSummary

    private var statusTag: (String, Color) {
        if session.dose2Skipped { return ("Skipped", .orange) }
        guard let iv = session.intervalMinutes else {
            if session.dose1Time != nil { return ("D1 Only", .yellow) }
            return ("No Doses", .gray)
        }
        if (150...165).contains(iv) { return ("On Time", .green) }
        if iv > 165 && iv <= 240 { return ("Late", .red) }
        return ("Out of Window", .red)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.sessionDate)
                    .font(.subheadline.bold())
                Spacer()
                Text(statusTag.0)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusTag.1.opacity(0.2)))
                    .foregroundColor(statusTag.1)
            }

            HStack(spacing: 12) {
                if let d1 = session.dose1Time {
                    Label(d1.formatted(date: .omitted, time: .shortened), systemImage: "1.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                if let d2 = session.dose2Time {
                    Label(d2.formatted(date: .omitted, time: .shortened), systemImage: "2.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                if let iv = session.intervalMinutes {
                    Label(TimeIntervalMath.formatMinutes(iv), systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }

            if !session.sleepEvents.isEmpty {
                let eventNames = Array(Set(session.sleepEvents.map(\.eventType))).sorted().prefix(5)
                HStack(spacing: 4) {
                    ForEach(eventNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    if session.sleepEvents.count > 5 {
                        Text("+\(session.sleepEvents.count - 5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Preview
#Preview {
    let container = AppContainer()
    return ContentView()
        .environmentObject(container)
        .environmentObject(container.settings)
        .environmentObject(container.sessionRepository)
        .environmentObject(container.alarmService)
}
