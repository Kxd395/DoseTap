//
//  NightReviewView.swift
//  DoseTap
//
//  Comprehensive night review dashboard showing:
//  - Pre-Sleep Log answers
//  - Morning Check-in answers
//  - Dose timing (Dose 1 → Dose 2 interval)
//  - Sleep events (bathroom, wake events, etc.)
//  - Apple Health sleep data
//  - WHOOP sleep/recovery data
//

import Foundation
import SwiftUI
import DoseCore

// MARK: - Night Review View
struct NightReviewView: View {
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var selectedSessionKey: String
    @State private var availableSessions: [String] = []
    
    init(sessionKey: String? = nil) {
        let defaultKey = SessionRepository.shared.currentSessionKey
        _selectedSessionKey = State(initialValue: sessionKey ?? defaultKey)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Session Picker
                    SessionPickerCard(
                        selectedSession: $selectedSessionKey,
                        availableSessions: availableSessions
                    )
                    
                    // Dose Timing Summary
                    DoseTimingCard(sessionKey: selectedSessionKey)
                    
                    // Night Score
                    NightScoreCard(sessionKey: selectedSessionKey)
                    
                    // Pre-Sleep Log Section
                    PreSleepLogCard(sessionKey: selectedSessionKey)
                    
                    // Morning Check-in Section
                    MorningCheckInCard(sessionKey: selectedSessionKey)
                    
                    // Sleep Events Timeline
                    SleepEventsCard(sessionKey: selectedSessionKey)
                    
                    // Health Integrations
                    HealthDataCard(sessionKey: selectedSessionKey)
                    
                    // Export Button
                    ExportCard(sessionKey: selectedSessionKey)
                }
                .padding()
            }
            .navigationTitle("Night Review")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { loadAvailableSessions() }
        }
    }
    
    private func loadAvailableSessions() {
        // Get last 30 session keys
        availableSessions = sessionRepo.getRecentSessionKeys(limit: 30)
        if !availableSessions.contains(selectedSessionKey), let first = availableSessions.first {
            selectedSessionKey = first
        }
    }
}

// MARK: - Session Picker
struct SessionPickerCard: View {
    @Binding var selectedSession: String
    let availableSessions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Night")
                .font(.headline)
            
            Picker("Session", selection: $selectedSession) {
                ForEach(availableSessions, id: \.self) { session in
                    Text(formatSessionDate(session)).tag(session)
                }
            }
            .pickerStyle(.menu)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func formatSessionDate(_ key: String) -> String {
        guard let date = AppFormatters.sessionDate.date(from: key) else { return key }
        return AppFormatters.weekdayMedium.string(from: date)
    }
}

// MARK: - Preview
#if DEBUG
struct NightReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NightReviewView()
    }
}
#endif
