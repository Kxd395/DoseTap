import SwiftUI

// Extracted from SettingsView.swift — Data management and session deletion

// MARK: - Data Management View
struct DataManagementView: View {
    @State private var sessions: [SessionSummary] = []
    @State private var selectedSessions: Set<String> = []
    @State private var isSelecting = false
    @State private var showHistoryChangeFailure = false
    @State private var showDeleteConfirmation = false
    @State private var showClearTonightConfirmation = false
    @State private var showClearTonightFailure = false
    @State private var showClearAllEventsConfirmation = false
    @State private var showClearOldDataConfirmation = false
    
    private let sessionRepo = SessionRepository.shared
    
    var body: some View {
        List {
            // Quick Actions Section
            Section {
                Button {
                    showClearTonightFailure = false
                    showClearTonightConfirmation = true
                } label: {
                    Label("Clear Tonight's Events", systemImage: "moon.stars")
                }
                
                if showClearTonightFailure {
                    Text("Couldn’t clear tonight’s sleep events. Try again.")
                        .foregroundStyle(.primary)
                }

                Button {
                    showClearOldDataConfirmation = true
                } label: {
                    Label("Clear Data Older Than 30 Days", systemImage: "calendar.badge.minus")
                }
                
                Button(role: .destructive) {
                    showClearAllEventsConfirmation = true
                } label: {
                    Label("Clear All Event History", systemImage: "trash")
                }
            } header: {
                Text("Quick Actions")
            }
            
            // Session List Section
            Section {
                if sessions.isEmpty {
                    Text("No session history")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(sessions, id: \.sessionDate) { session in
                        SessionDeleteRow(
                            session: session,
                            isSelecting: isSelecting,
                            isSelected: selectedSessions.contains(session.sessionDate),
                            onToggle: {
                                if selectedSessions.contains(session.sessionDate) {
                                    selectedSessions.remove(session.sessionDate)
                                } else {
                                    selectedSessions.insert(session.sessionDate)
                                }
                            }
                        )
                    }
                    .onDelete(perform: deleteSessions)
                }
            } header: {
                HStack {
                    Text("Sessions (\(sessions.count))")
                    Spacer()
                    if !sessions.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedSessions.removeAll()
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if isSelecting && !selectedSessions.isEmpty {
                        Text("\(selectedSessions.count) selected")
                        
                        // Prominent delete button when items are selected
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete \(selectedSessions.count) Session\(selectedSessions.count == 1 ? "" : "s")")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Swipe to delete individual sessions, or tap Select for multi-delete.")
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Manage History")
        .toolbar {
            if isSelecting && !selectedSessions.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete \(selectedSessions.count) Sessions", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear { loadSessions() }
        .alert("History change incomplete", isPresented: $showHistoryChangeFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Review the remaining records and try again.")
        }
        // Delete Selected Confirmation
        .alert("Delete Selected Sessions?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedSessions.count)", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text("This will permanently delete \(selectedSessions.count) session(s) and their events. This cannot be undone.")
        }
        // Clear Tonight Confirmation
        .alert("Clear Tonight's Events?", isPresented: $showClearTonightConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearTonightsEvents()
            }
        } message: {
            Text("This will delete tonight’s sleep and quick-log events. Your dose records and reminders will be preserved.")
        }
        // Clear All Events Confirmation
        .alert("Clear All Event History?", isPresented: $showClearAllEventsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllEvents()
            }
        } message: {
            Text("This will permanently delete all sleep events from all sessions. Dose logs will be preserved.")
        }
        // Clear Old Data Confirmation
        .alert("Clear Old Data?", isPresented: $showClearOldDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearOldData()
            }
        } message: {
            Text("This will delete all sessions and events older than 30 days.")
        }
    }
    
    private func loadSessions() {
        sessions = sessionRepo.fetchRecentSessions(days: 365) // Get up to a year
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        deleteSessionDates(Set(offsets.map { sessions[$0].sessionDate }))
    }

    private func deleteSelectedSessions() {
        deleteSessionDates(selectedSessions)
        isSelecting = !selectedSessions.isEmpty
    }

    private func deleteSessionDates(_ dates: Set<String>) {
        for date in dates {
            if sessionRepo.deleteSession(sessionDate: date) {
                selectedSessions.remove(date)
            } else {
                showHistoryChangeFailure = true
            }
        }
        loadSessions()
    }

    private func clearTonightsEvents() {
        guard sessionRepo.clearTonightsEvents() else {
            showClearTonightFailure = true
            return
        }
        loadSessions()
    }
    
    private func clearAllEvents() {
        sessionRepo.clearAllSleepEvents()
        loadSessions()
    }
    
    private func clearOldData() {
        if !sessionRepo.clearOldData(olderThanDays: 30) { showHistoryChangeFailure = true }
        loadSessions()
    }
}

// MARK: - Session Delete Row
struct SessionDeleteRow: View {
    let session: SessionSummary
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            if isSelecting {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.subheadline.bold())
                
                HStack(spacing: 12) {
                    if session.dose1Time != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "1.circle.fill")
                                .font(.caption2)
                            Text(session.dose1Time!.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    }
                    
                    if session.dose2Time != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "2.circle.fill")
                                .font(.caption2)
                            Text(session.dose2Time!.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    } else if session.skipped {
                        Text("Skipped")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if session.eventCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.caption2)
                            Text("\(session.eventCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggle()
            }
        }
    }
    
    private var formattedDate: String {
        // Convert session date string to formatted display
        if let date = AppFormatters.sessionDate.date(from: session.sessionDate) {
            return AppFormatters.shortWeekday.string(from: date)
        }
        return session.sessionDate
    }
}
