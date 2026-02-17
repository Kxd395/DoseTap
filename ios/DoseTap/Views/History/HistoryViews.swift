import SwiftUI
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

struct HistoryView: View {
    @Environment(\.isInSplitView) private var isInSplitView
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDate = Date()
    @State private var pastSessions: [SessionSummary] = []
    @State private var showDeleteDayConfirmation = false
    @State private var refreshTrigger = false  // Toggled to force SelectedDayView refresh
    
    private let sessionRepo = SessionRepository.shared

    private var isWideLayout: Bool { horizontalSizeClass == .regular }
    
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
            if isWideLayout {
                // iPad: side-by-side calendar + selected day detail
                wideHistoryLayout
            } else {
                // iPhone: stacked vertical layout
                compactHistoryLayout
            }
        }
        .navigationTitle("History")
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
        }
        .padding()
        .padding(.bottom, 80)
    }
    
    private func loadHistory() {
        pastSessions = sessionRepo.fetchRecentSessions(days: 7)
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

// MARK: - Full Session Details
struct FullSessionDetails: View {
    @ObservedObject var core: DoseTapCore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Details")
                .font(.headline)
            
            // Dose Times
            VStack(spacing: 12) {
                DetailRow(
                    icon: "1.circle.fill",
                    title: "Dose 1",
                    value: core.dose1Time?.formatted(date: .abbreviated, time: .shortened) ?? "Not taken",
                    color: .blue
                )
                
                DetailRow(
                    icon: "2.circle.fill",
                    title: "Dose 2",
                    value: dose2String,
                    color: .green
                )
                
                if let dose1 = core.dose1Time {
                    DetailRow(
                        icon: "clock.fill",
                        title: "Window Opens",
                        value: dose1.addingTimeInterval(150 * 60).formatted(date: .omitted, time: .shortened),
                        color: .orange
                    )
                    
                    DetailRow(
                        icon: "clock.badge.exclamationmark.fill",
                        title: "Window Closes",
                        value: dose1.addingTimeInterval(240 * 60).formatted(date: .omitted, time: .shortened),
                        color: .red
                    )
                    
                    if let dose2 = core.dose2Time {
                        let interval = TimeIntervalMath.minutesBetween(start: dose1, end: dose2)
                        DetailRow(
                            icon: "timer",
                            title: "Interval",
                            value: TimeIntervalMath.formatMinutes(interval),
                            color: .purple
                        )
                    }
                }
                
                DetailRow(
                    icon: "bell.badge.fill",
                    title: "Snoozes Used",
                    value: "\(core.snoozeCount) of 3",
                    color: .orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var dose2String: String {
        if let time = core.dose2Time {
            return time.formatted(date: .abbreviated, time: .shortened)
        }
        if core.isSkipped { return "Skipped" }
        return "Pending"
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Full Event Log Grid (4x3)
struct FullEventLogGrid: View {
    let eventTypes: [(name: String, icon: String, color: Color)]
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings: UserSettingsManager
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Log Sleep Event")
                    .font(.headline)
                Spacer()
                Text("Tap to log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(eventTypes, id: \.name) { event in
                    let cooldown = settings.cooldown(for: event.name)
                    EventGridButton(
                        name: event.name,
                        icon: event.icon,
                        color: event.color,
                        cooldownEnd: eventLogger.cooldownEnd(for: event.name),
                        cooldownDuration: cooldown,
                        lastLogTime: eventLogger.lastEventTime(for: event.name),
                        onTap: {
                            eventLogger.logEvent(name: event.name, color: event.color, cooldownSeconds: cooldown)
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct EventGridButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownEnd: Date?
    let cooldownDuration: TimeInterval
    let lastLogTime: Date?
    let onTap: () -> Void
    
    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }
    
    /// P3-4: Relative "time since" badge text
    private var timeSinceBadge: String? {
        guard !isOnCooldown else { return nil }
        return EventLogger.relativeBadge(since: lastLogTime)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(isOnCooldown ? 0.1 : 0.15))
                        .frame(height: 60)
                    
                    if isOnCooldown {
                        RoundedRectangle(cornerRadius: 12)
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.3), lineWidth: 2)
                            .frame(height: 60)
                    }
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }
                
                Text(name)
                    .font(.caption2)
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // P3-4: "time since" badge
                if let badge = timeSinceBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(color.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
        }
        .disabled(isOnCooldown)
        .onReceive(timer) { _ in
            guard let end = cooldownEnd else { progress = 1.0; return }
            let remaining = end.timeIntervalSince(Date())
            progress = remaining <= 0 ? 1.0 : 1.0 - CGFloat(remaining / cooldownDuration)
        }
    }
}

// MARK: - Event History Section
struct EventHistorySection: View {
    let events: [LoggedEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event History")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    HStack {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        Text(event.name)
                            .font(.subheadline)
                        Spacer()
                        Text(event.time, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Supporting Views (from original)

struct StatusCard: View {
    let status: DoseStatus
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                Text(statusTitle)
                    .font(.headline)
            }
            .foregroundColor(statusColor)
            
            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusIcon: String {
        switch status {
        case .noDose1: return "1.circle"
        case .beforeWindow: return "clock"
        case .active: return "checkmark.circle"
        case .nearClose: return "exclamationmark.triangle"
        case .closed: return "xmark.circle"
        case .completed: return "checkmark.seal.fill"
        case .finalizing: return "sunrise.fill"
        }
    }
    
    private var statusTitle: String {
        switch status {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Window Closing Soon"
        case .closed: return "Window Closed"
        case .completed: return "Complete"
        case .finalizing: return "Finalizing Session"
        }
    }
    
    private var statusDescription: String {
        switch status {
        case .noDose1: return "Take Dose 1 to start your session"
        case .beforeWindow: return "Dose 2 window opens in \(TimeIntervalMath.formatMinutes(150))"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than \(TimeIntervalMath.formatMinutes(15)) remaining!"
        case .closed: return "Window closed (\(TimeIntervalMath.formatMinutes(240)) max)"
        case .completed: return "Both doses taken ✓"
        case .finalizing: return "Complete morning check-in"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .gray
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }
}

struct TimeUntilWindowCard: View {
    let dose1Time: Date
    @State private var timeRemaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let windowOpenMinutes: TimeInterval = 150
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Window Opens In")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(formatTimeRemaining)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .monospacedDigit()
            
            Text("Take Dose 2 after \(formatWindowOpenTime)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }
    
    private func updateTimeRemaining() {
        let windowOpenTime = dose1Time.addingTimeInterval(windowOpenMinutes * 60)
        timeRemaining = max(0, windowOpenTime.timeIntervalSince(Date()))
    }
    
    private var formatTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var formatWindowOpenTime: String {
        dose1Time.addingTimeInterval(windowOpenMinutes * 60).formatted(date: .omitted, time: .shortened)
    }
}

struct DoseButtonsSection: View {
    @ObservedObject var core: DoseTapCore
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @State private var showWindowExpiredOverride = false
    
    /// P0-4: Centralised coordinator for all dose actions
    var coordinator: DoseActionCoordinator?
    
    private let windowOpenMinutes: Double = 150
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            .disabled(primaryButtonDisabled)
            .alert("Window Expired", isPresented: $showWindowExpiredOverride) {
                Button("Cancel", role: .cancel) { }
                Button("Take Dose 2 Anyway", role: .destructive) {
                    Task {
                        if let coord = coordinator {
                            let _ = await coord.takeDose2(override: .lateConfirmed)
                        } else {
                            await core.takeDose(lateOverride: true)
                            AlarmService.shared.cancelAllAlarms()
                            AlarmService.shared.clearDose2AlarmState()
                        }
                    }
                }
            } message: {
                Text("The 240-minute window has passed. Taking Dose 2 late may affect efficacy.")
            }
            
            if core.currentStatus == .beforeWindow {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Dose 2 window not yet open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button("Snooze +10m") {
                    Task {
                        if let coord = coordinator {
                            let _ = await coord.snooze()
                        } else {
                            await core.snooze()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!snoozeEnabled)
                
                Button("Skip Dose") {
                    Task {
                        if let coord = coordinator {
                            let _ = await coord.skipDose()
                        } else {
                            await core.skipDose()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!skipEnabled)
            }
        }
    }
    
    private func handlePrimaryButtonTap() {
        if let coord = coordinator {
            Task {
                let isDose1 = core.dose1Time == nil
                let result = isDose1 ? await coord.takeDose1() : await coord.takeDose2()
                switch result {
                case .success:
                    break
                case .needsConfirm(let confirmation):
                    switch confirmation {
                    case .earlyDose(let minutes):
                        earlyDoseMinutes = minutes
                        showEarlyDoseAlert = true
                    case .lateDose, .afterSkip:
                        showWindowExpiredOverride = true
                    case .extraDose:
                        showWindowExpiredOverride = true
                    }
                case .blocked:
                    break
                }
            }
            return
        }
        // Legacy fallback
        guard core.dose1Time != nil else {
            Task { await core.takeDose() }
            return
        }
        
        if core.currentStatus == .beforeWindow {
            if let dose1Time = core.dose1Time {
                let remaining = dose1Time.addingTimeInterval(windowOpenMinutes * 60).timeIntervalSince(Date())
                earlyDoseMinutes = max(1, Int(ceil(remaining / 60)))
            }
            showEarlyDoseAlert = true
            return
        }

        if core.currentStatus == .closed {
            showWindowExpiredOverride = true
            return
        }

        if core.currentStatus == .completed, core.isSkipped, core.dose2Time == nil {
            showWindowExpiredOverride = true
            return
        }
        
        Task { await core.takeDose() }
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Take Dose 2 (Late)"
        case .completed: return "Complete ✓"
        case .finalizing: return "Check-In"
        }
    }
    
    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .orange
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }
    
    private var snoozeEnabled: Bool {
        if case .snoozeEnabled = core.windowContext.snooze { return true }
        return false
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose || core.currentStatus == .closed
    }

    private var primaryButtonDisabled: Bool {
        if core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil {
            return false
        }
        return core.currentStatus == .completed
    }
}

// MARK: - Early Dose Override Sheet
struct EarlyDoseOverrideSheet: View {
    let minutesRemaining: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    private let requiredHoldDuration: CGFloat = 3.0
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Override Dose Timing")
                    .font(.title2.bold())
                
                Text("Hold to confirm early dose")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 12) {
                WarningRow(icon: "clock.badge.exclamationmark", text: "\(TimeIntervalMath.formatMinutes(minutesRemaining)) early", color: .orange)
                WarningRow(icon: "pills.fill", text: "May reduce effectiveness", color: .red)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 12) {
                Text("Hold for 3 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: holdProgress)
                    
                    Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                        .font(.title)
                        .foregroundColor(isHolding ? .red : .gray)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isHolding { startHolding() } }
                        .onEnded { _ in stopHolding() }
                )
            }
            
            Button("Cancel") { onCancel() }
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.bottom, 30)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func startHolding() {
        isHolding = true
        holdProgress = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            holdProgress += 0.05 / requiredHoldDuration
            if holdProgress >= 1.0 {
                holdTimer?.invalidate()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onConfirm()
            }
        }
    }
    
    private func stopHolding() {
        isHolding = false
        holdTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
    }
}

struct WarningRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
