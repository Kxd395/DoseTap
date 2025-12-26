import SwiftUI
import Combine
import DoseCore

/// Timeline view showing historical dose sessions and sleep events
/// Per SSOT: Timeline Screen shows historical dose events and patterns
public struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    // Multi-select state - uses canonical session key (yyyy-MM-dd, 6PM rollover)
    @State private var isEditMode = false
    @State private var selectedSessionKeys: Set<String> = []
    @State private var showingDeleteConfirmation = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .ready:
                    timelineContent
                case .empty:
                    emptyView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                // Edit/Done button (leading)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditMode ? "Done" : "Select") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedSessionKeys.removeAll()
                            }
                        }
                    }
                }
                
                // Delete button when in edit mode (trailing)
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode && !selectedSessionKeys.isEmpty {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete (\(selectedSessionKeys.count))", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    } else {
                        Menu {
                            Button(action: { viewModel.exportCSV() }) {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                            Button(action: { viewModel.refresh() }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Delete Sessions?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedSessionKeys.count) Session\(selectedSessionKeys.count == 1 ? "" : "s")", role: .destructive) {
                    deleteSelectedSessions()
                }
            } message: {
                Text("This will permanently delete the selected session\(selectedSessionKeys.count == 1 ? "" : "s") and all associated events. This cannot be undone.")
            }
        }
        .task {
            await viewModel.load()
        }
    }
    
    private func deleteSelectedSessions() {
        for key in selectedSessionKeys {
            viewModel.deleteSession(sessionKey: key)
        }
        selectedSessionKeys.removeAll()
        isEditMode = false
        Task {
            await viewModel.load()
        }
    }
    
    private func toggleSelection(for session: TimelineSession) {
        // Use canonical sessionKey to respect 6PM rollover
        let key = session.sessionKey
        if selectedSessionKeys.contains(key) {
            selectedSessionKeys.remove(key)
        } else {
            selectedSessionKeys.insert(key)
        }
    }
    
    private func isSelected(_ session: TimelineSession) -> Bool {
        selectedSessionKeys.contains(session.sessionKey)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading timeline...")
                .foregroundColor(.secondary)
        }
    }
    
    private var timelineContent: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.groupedSessions.keys.sorted().reversed(), id: \.self) { date in
                    Section {
                        if let sessions = viewModel.groupedSessions[date] {
                            ForEach(sessions) { session in
                                HStack(spacing: 12) {
                                    // Selection checkbox (only in edit mode)
                                    if isEditMode {
                                        Button {
                                            toggleSelection(for: session)
                                        } label: {
                                            Image(systemName: isSelected(session) ? "checkmark.circle.fill" : "circle")
                                                .font(.title2)
                                                .foregroundColor(isSelected(session) ? .blue : .gray)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    TimelineSessionCard(session: session)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if isEditMode {
                                                toggleSelection(for: session)
                                            }
                                        }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            TimelineSectionHeader(date: date)
                            
                            // Select All for this date
                            if isEditMode, let sessions = viewModel.groupedSessions[date] {
                                Spacer()
                                let sessionKeys = Set(sessions.map { $0.sessionKey })
                                Button {
                                    if sessionKeys.isSubset(of: selectedSessionKeys) {
                                        // Deselect all in this section
                                        selectedSessionKeys.subtract(sessionKeys)
                                    } else {
                                        // Select all in this section
                                        selectedSessionKeys.formUnion(sessionKeys)
                                    }
                                } label: {
                                    Text(sessionKeys.isSubset(of: selectedSessionKeys) ? "Deselect" : "Select All")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.load()
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Sessions Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your dose history will appear here\nafter you take your first dose.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Load Timeline")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// Section header with date
struct TimelineSectionHeader: View {
    let date: Date
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var isYesterday: Bool {
        Calendar.current.isDateInYesterday(date)
    }
    
    var body: some View {
        HStack {
            Text(displayText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
    }
    
    private var displayText: String {
        if isToday { return "Today" }
        if isYesterday { return "Yesterday" }
        return dateFormatter.string(from: date)
    }
}

/// Card showing a single session with dose times and events
struct TimelineSessionCard: View {
    let session: TimelineSession
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with dose times
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        doseTimeView(label: "Dose 1", time: session.dose1Time, color: .blue)
                        
                        if let dose2 = session.dose2Time {
                            doseTimeView(label: "Dose 2", time: dose2, color: .green)
                        } else if session.dose2Skipped {
                            skipBadge
                        } else {
                            pendingBadge
                        }
                    }
                }
                
                Spacer()
                
                // Interval badge
                if let interval = session.intervalMinutes {
                    intervalBadge(minutes: interval)
                }
            }
            
            // Snooze indicator
            if session.snoozeCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.orange)
                    Text("\(session.snoozeCount) snooze\(session.snoozeCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sleep events summary
            if !session.sleepEvents.isEmpty {
                Divider()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Text("\(session.sleepEvents.count) event\(session.sleepEvents.count == 1 ? "" : "s") logged")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.sleepEvents) { event in
                            sleepEventRow(event)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }
    
    private func doseTimeView(label: String, time: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(timeFormatter.string(from: time))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private var skipBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dose 2")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Skipped")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.orange)
        }
    }
    
    private var pendingBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dose 2")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Pending")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
    }
    
    private func intervalBadge(minutes: Int) -> some View {
        let hours = minutes / 60
        let mins = minutes % 60
        let inRange = minutes >= 150 && minutes <= 240
        
        return VStack(alignment: .trailing, spacing: 2) {
            Text("Interval")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(hours)h \(mins)m")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(inRange ? .green : .orange)
        }
    }
    
    private func sleepEventRow(_ event: TimelineSleepEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.iconName)
                .foregroundColor(event.color)
                .frame(width: 20)
            
            Text(event.displayName)
                .font(.caption)
            
            Spacer()
            
            Text(timeFormatter.string(from: event.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
}

// MARK: - View Model

@MainActor
class TimelineViewModel: ObservableObject {
    enum State {
        case loading
        case ready
        case empty
        case error(String)
    }
    
    @Published var state: State = .loading
    @Published var groupedSessions: [Date: [TimelineSession]] = [:]
    
    // Use SessionRepository as the single source of truth
    private let sessionRepo = SessionRepository.shared
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    func load() async {
        state = .loading
        
        // Use SessionRepository as the single source of truth
        let sleepEvents = sessionRepo.fetchAllSleepEvents(limit: 500)
        let doseLogs = sessionRepo.fetchAllDoseLogs(limit: 500)
        
        if sleepEvents.isEmpty && doseLogs.isEmpty {
            state = .empty
            return
        }
        
        // Build sessions from dose logs and sleep events
        var sessions = buildSessionsFromEventStorage(doseLogs: doseLogs, sleepEvents: sleepEvents)
        
        // Filter out sessions that no longer exist (deleted/soft-deleted)
        let formatter = dateFormatter
        let sessionDates = sessions.map { formatter.string(from: $0.date) }
        let allowedDates = Set(sessionRepo.filterExistingSessionDates(sessionDates))
        sessions = sessions.filter { allowedDates.contains(formatter.string(from: $0.date)) }
        
        if sessions.isEmpty {
            state = .empty
            return
        }
        
        // Group sessions by date
        groupedSessions = Dictionary(grouping: sessions) { session in
            Calendar.current.startOfDay(for: session.date)
        }
        
        state = .ready
    }
    
    func refresh() {
        Task {
            await load()
        }
    }
    
    func exportCSV() {
        let csv = sessionRepo.exportToCSV()
        // TODO: Present share sheet with CSV
        print("CSV Export:\n\(csv)")
    }
    
    /// Delete a session by its canonical session key (yyyy-MM-dd)
    /// P0-5 FIX: Route through SessionRepository to ensure notifications are cancelled
    /// and in-memory state is properly cleared for active session
    func deleteSession(sessionKey: String) {
        // Validate session key format (yyyy-MM-dd)
        guard dateFormatter.date(from: sessionKey) != nil else { return }
        
        // Route through SessionRepository - this ensures:
        // 1. If this is the active session, in-memory state is cleared
        // 2. Pending notifications are cancelled
        // 3. sessionDidChange signal is broadcast
        sessionRepo.deleteSession(sessionDate: sessionKey)
        
        // Refresh to reflect changes
        refresh()
    }
    
    /// Build sessions from EventStorage dose logs and sleep events
    private func buildSessionsFromEventStorage(doseLogs: [StoredDoseLog], sleepEvents: [StoredSleepEvent]) -> [TimelineSession] {
        var sessionMap: [String: TimelineSession] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Build sessions from dose logs
        for log in doseLogs {
            let sessionDate = dateFormatter.date(from: log.sessionDate) ?? Date()
            
            let session = TimelineSession(
                id: UUID(),
                sessionKey: log.sessionDate,
                date: sessionDate,
                dose1Time: log.dose1Time,
                dose2Time: log.dose2Time,
                dose2Skipped: log.dose2Skipped,
                snoozeCount: log.snoozeCount,
                sleepEvents: []
            )
            sessionMap[log.sessionDate] = session
        }
        
        // Associate sleep events with sessions by sessionDate
        for event in sleepEvents {
            let sessionKey = event.sessionDate
            if var session = sessionMap[sessionKey] {
                let sleepEvent = TimelineSleepEvent(
                    id: event.id,
                    eventType: event.eventType,
                    timestamp: event.timestamp,
                    notes: event.notes,
                    source: "manual"
                )
                session = TimelineSession(
                    id: session.id,
                    sessionKey: session.sessionKey,
                    date: session.date,
                    dose1Time: session.dose1Time,
                    dose2Time: session.dose2Time,
                    dose2Skipped: session.dose2Skipped,
                    snoozeCount: session.snoozeCount,
                    sleepEvents: session.sleepEvents + [sleepEvent]
                )
                sessionMap[sessionKey] = session
            } else {
                // Create a session just from sleep events if no dose log exists
                let sessionDate = dateFormatter.date(from: sessionKey) ?? event.timestamp
                let sleepEvent = TimelineSleepEvent(
                    id: event.id,
                    eventType: event.eventType,
                    timestamp: event.timestamp,
                    notes: event.notes,
                    source: "manual"
                )
                sessionMap[sessionKey] = TimelineSession(
                    id: UUID(),
                    sessionKey: sessionKey,
                    date: sessionDate,
                    dose1Time: event.timestamp,
                    dose2Time: nil,
                    dose2Skipped: false,
                    snoozeCount: 0,
                    sleepEvents: [sleepEvent]
                )
            }
        }
        
        return Array(sessionMap.values).sorted { $0.date > $1.date }
    }
}

// MARK: - Models

struct TimelineSession: Identifiable {
    let id: UUID
    let sessionKey: String
    let date: Date
    let dose1Time: Date
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let sleepEvents: [TimelineSleepEvent]
    
    var intervalMinutes: Int? {
        guard let d2 = dose2Time else { return nil }
        return Int(d2.timeIntervalSince(dose1Time) / 60)
    }
}

struct TimelineSleepEvent: Identifiable {
    let id: String  // Changed from UUID to String to match StoredSleepEvent
    let type: String
    let timestamp: Date
    let notes: String?
    let source: String
    
    // Convenience initializer for new structure
    init(id: String, eventType: String, timestamp: Date, notes: String?, source: String) {
        self.id = id
        self.type = eventType
        self.timestamp = timestamp
        self.notes = notes
        self.source = source
    }
    
    // Legacy initializer for compatibility
    init(id: UUID, type: String, timestamp: Date) {
        self.id = id.uuidString
        self.type = type
        self.timestamp = timestamp
        self.notes = nil
        self.source = "manual"
    }
    
    var displayName: String {
        switch type {
        case "bathroom": return "Bathroom"
        case "water": return "Water"
        case "lightsOut": return "Lights Out"
        case "wakeFinal": return "Wake Up"
        case "wakeTemp": return "Brief Wake"
        case "anxiety": return "Anxiety"
        case "pain": return "Pain"
        case "noise": return "Noise"
        case "snack": return "Snack"
        case "dream": return "Dream"
        case "temperature": return "Temperature"
        case "heartRacing": return "Heart Racing"
        default: return type.capitalized
        }
    }
    
    var iconName: String {
        switch type {
        case "bathroom": return "toilet.fill"
        case "water": return "drop.fill"
        case "lightsOut": return "light.max"
        case "wakeFinal": return "sun.max.fill"
        case "wakeTemp": return "moon.zzz.fill"
        case "anxiety": return "brain.head.profile"
        case "pain": return "bandage.fill"
        case "noise": return "speaker.wave.3.fill"
        case "snack": return "fork.knife"
        case "dream": return "cloud.moon.fill"
        case "temperature": return "thermometer.medium"
        case "heartRacing": return "heart.fill"
        default: return "circle.fill"
        }
    }
    
    var color: Color {
        switch type {
        case "bathroom": return .blue
        case "water": return .cyan
        case "lightsOut": return .purple
        case "wakeFinal": return .orange
        case "wakeTemp": return .indigo
        case "anxiety": return .pink
        case "pain": return .red
        case "noise": return .gray
        case "snack": return .brown
        case "dream": return .purple
        case "temperature": return .orange
        case "heartRacing": return .red
        default: return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
    }
}
#endif
