import SwiftUI
import DoseCore
import os.log

private let tonightLogger = Logger(subsystem: "com.dosetap.app", category: "TonightView")

struct TonightView: View {
    @StateObject private var doseCore = DoseCoreIntegration()
    @StateObject private var quickLogViewModel = QuickLogViewModel()
    @State private var showingError = false
    @State private var showMorningCheckIn = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Window Status Header
                    WindowStatusCard(context: doseCore.currentContext)
                    
                    // Main Action Buttons
                    ActionButtonsSection(doseCore: doseCore)
                    
                    // Quick Log Panel - Sleep Event Buttons
                    QuickLogSection(viewModel: quickLogViewModel, doseCore: doseCore)
                    
                    // Wake Up & End Session Button
                    WakeUpEndSessionButton(
                        doseCore: doseCore,
                        showMorningCheckIn: $showMorningCheckIn
                    )
                    
                    // Tonight's Sleep Events (expandable list of all logged events)
                    TonightEventsSection(viewModel: quickLogViewModel, doseCore: doseCore)
                    
                    // Recent Dose Events (dose1, dose2, snooze, skip)
                    if !doseCore.recentEvents.isEmpty {
                        RecentEventsSection(events: Array(doseCore.recentEvents.prefix(5)))
                    }
                }
                .padding()
            }
            .navigationTitle("Tonight")
            .alert("Error", isPresented: $showingError) {
                Button("OK") { doseCore.lastError = nil }
            } message: {
                Text(doseCore.lastError ?? "Unknown error")
            }
            .onChange(of: doseCore.lastError) { error in
                showingError = error != nil
            }
            .sheet(isPresented: $showMorningCheckIn) {
                MorningCheckInView(
                    sessionId: SessionRepository.shared.currentSessionIdString(),
                    sessionDate: SessionRepository.shared.currentSessionDateString(),
                    onComplete: {
                        tonightLogger.info("Morning check-in complete")
                    }
                )
            }
        }
    }
}

// MARK: - Tonight's Events Section (All Logged Sleep Events)
struct TonightEventsSection: View {
    @ObservedObject var viewModel: QuickLogViewModel
    @ObservedObject var doseCore: DoseCoreIntegration
    @State private var isExpanded = false
    
    private var tonightEvents: [StoredSleepEvent] {
        // Get all sleep events for tonight's session via SessionRepository
        SessionRepository.shared.fetchTonightSleepEvents()
    }
    
    var body: some View {
        if !tonightEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header with count and expand/collapse
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundColor(.blue)
                        
                        Text("Tonight's Events")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("(\(tonightEvents.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Expanded event list
                if isExpanded {
                    Divider()
                    
                    ForEach(tonightEvents, id: \.id) { event in
                        TonightEventRow(event: event)
                    }
                } else {
                    // Collapsed preview - show first 3 events
                    ForEach(Array(tonightEvents.prefix(3)), id: \.id) { event in
                        TonightEventRow(event: event)
                    }
                    
                    if tonightEvents.count > 3 {
                        Text("+ \(tonightEvents.count - 3) more events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct TonightEventRow: View {
    let event: StoredSleepEvent
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForEvent(event.eventType))
                .foregroundColor(colorForEvent(event.eventType))
                .frame(width: 24)
            
            Text(displayName(for: event.eventType))
                .font(.subheadline)
            
            Spacer()
            
            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    /// Normalize event type to canonical snake_case format
    private func normalized(_ eventType: String) -> String {
        let lower = eventType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch lower {
        case "lightsout", "lights_out":   return "lights_out"
        case "inbed", "in_bed":           return "in_bed"
        case "wakefinal", "wake_final":   return "wake_final"
        case "waketemp", "wake_temp", "brief_wake": return "brief_wake"
        case "heartracing", "heart_racing": return "heart_racing"
        case "napstart", "nap_start":     return "nap_start"
        case "napend", "nap_end":         return "nap_end"
        default: return lower.replacingOccurrences(of: " ", with: "_")
        }
    }

    private func displayName(for eventType: String) -> String {
        switch normalized(eventType) {
        case "bathroom": return "Bathroom"
        case "water": return "Water"
        case "lights_out": return "Lights Out"
        case "in_bed": return "In Bed"
        case "wake_final": return "Wake Up"
        case "brief_wake": return "Brief Wake"
        case "anxiety": return "Anxiety"
        case "pain": return "Pain"
        case "noise": return "Noise"
        case "snack": return "Snack"
        case "dream": return "Dream"
        case "temperature": return "Temperature"
        case "heart_racing": return "Heart Racing"
        case "nap_start": return "Nap Start"
        case "nap_end": return "Nap End"
        default: return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func iconForEvent(_ eventType: String) -> String {
        switch normalized(eventType) {
        case "bathroom": return "toilet.fill"
        case "water": return "drop.fill"
        case "lights_out": return "light.max"
        case "in_bed": return "bed.double.fill"
        case "wake_final": return "sun.max.fill"
        case "brief_wake": return "moon.zzz.fill"
        case "anxiety": return "brain.head.profile"
        case "pain": return "bandage.fill"
        case "noise": return "speaker.wave.3.fill"
        case "snack": return "fork.knife"
        case "dream": return "cloud.moon.fill"
        case "temperature": return "thermometer.medium"
        case "heart_racing": return "heart.fill"
        case "nap_start": return "powersleep"
        case "nap_end": return "sun.min.fill"
        default: return "circle.fill"
        }
    }
    
    private func colorForEvent(_ eventType: String) -> Color {
        switch normalized(eventType) {
        case "bathroom": return .blue
        case "water": return .cyan
        case "lights_out": return .purple
        case "in_bed": return .indigo
        case "wake_final": return .orange
        case "brief_wake": return .indigo
        case "anxiety": return .pink
        case "pain": return .red
        case "noise": return .gray
        case "snack": return .brown
        case "dream": return .purple
        case "temperature": return .orange
        case "heart_racing": return .red
        case "nap_start", "nap_end": return .teal
        default: return .gray
        }
    }
}

// MARK: - Wake Up & End Session Button
struct WakeUpEndSessionButton: View {
    @ObservedObject var doseCore: DoseCoreIntegration
    @Binding var showMorningCheckIn: Bool
    
    var body: some View {
        Button {
            SessionRepository.shared.setWakeFinalTime(Date())
            // Show morning check-in
            showMorningCheckIn = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake Up & End Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Complete your morning check-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.yellow.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Quick Log Section (Sleep Events)
struct QuickLogSection: View {
    @ObservedObject var viewModel: QuickLogViewModel
    @ObservedObject var doseCore: DoseCoreIntegration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Sleep Events")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Use QuickLogPanel component
            QuickLogPanel(viewModel: viewModel)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct WindowStatusCard: View {
    let context: DoseWindowContext
    
    var body: some View {
        VStack(spacing: 12) {
            // Phase indicator
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 12, height: 12)
                Text(phaseText)
                    .font(.headline)
                    .foregroundColor(phaseColor)
                Spacer()
            }
            
            // Primary message
            Text(context.primaryCTA)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Timing info
            if let timeInfo = timingInfo {
                Text(timeInfo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var phaseColor: Color {
        switch context.phase {
        case .noDose1: return .gray
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .gray
        case .completed: return .blue
        case .finalizing: return .purple
        }
    }
    
    private var phaseText: String {
        switch context.phase {
        case .noDose1: return "Dose 1 Needed"
        case .beforeWindow: return "Before Window"
        case .active: return "Active Window" 
        case .nearClose: return "Window Closing"
        case .closed: return "Window Closed"
        case .completed: return "Complete"
        case .finalizing: return "Finalizing"
        }
    }
    
    private var timingInfo: String? {
        if let remaining = context.timeRemaining {
            return "\(Int(remaining / 60)) minutes remaining"
        } else if let elapsed = context.timeElapsed {
            return "\(Int(elapsed / 60)) minutes since Dose 1"
        }
        return nil
    }
}

struct ActionButtonsSection: View {
    @ObservedObject var doseCore: DoseCoreIntegration
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary action button (from context)
            Button(action: primaryAction) {
                Text(doseCore.currentContext.primaryCTA)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            .disabled(doseCore.isLoading)
            
            // Secondary actions
            HStack(spacing: 12) {
                if doseCore.currentContext.snoozeEnabled {
                    Button("Snooze +10m") {
                        Task { await doseCore.snooze() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(doseCore.isLoading)
                }
                
                if doseCore.currentContext.skipEnabled {
                    Button("Skip") {
                        Task { await doseCore.skipDose2() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(doseCore.isLoading)
                }
            }
        }
    }
    
    private var primaryButtonColor: Color {
        switch doseCore.currentContext.phase {
        case .noDose1, .beforeWindow, .completed: return .blue
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .gray
        case .finalizing: return .purple
        }
    }
    
    private func primaryAction() {
        Task {
            let context = doseCore.currentContext
            let cta = context.primaryCTA.lowercased()
            
            if cta.contains("dose 1") {
                await doseCore.takeDose1()
            } else if cta.contains("dose 2") || cta.contains("take") {
                await doseCore.takeDose2()
            }
        }
    }
}

struct RecentEventsSection: View {
    let events: [DoseEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(events) { event in
                HStack {
                    Image(systemName: iconForEvent(event.type))
                        .foregroundColor(colorForEvent(event.type))
                        .frame(width: 20)
                    
                    Text(event.type.rawValue.capitalized)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func iconForEvent(_ type: DoseEventType) -> String {
        switch type {
        case .dose1, .dose2: return "pills.fill"
        case .snooze: return "clock.fill"
        case .skip: return "xmark.circle.fill"
        case .bathroom: return "figure.walk"
        case .lightsOut: return "lightbulb.slash.fill"
        case .wakeFinal: return "sun.max.fill"
        }
    }
    
    private func colorForEvent(_ type: DoseEventType) -> Color {
        switch type {
        case .dose1, .dose2: return .blue
        case .snooze: return .orange
        case .skip: return .red
        case .bathroom: return .purple
        case .lightsOut: return .indigo
        case .wakeFinal: return .yellow
        }
    }
}

#Preview {
    TonightView()
}
