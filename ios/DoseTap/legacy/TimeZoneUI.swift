// iOS/TimeZoneUI.swift
import SwiftUI
import CoreLocation

// iOS/TimeZoneUI.swift
#if os(iOS)
import SwiftUI
import MapKit

// MARK: - Time Zone Models

struct TimeZoneDetectionView: View {
    @StateObject private var timeZoneMonitor = TimeZoneMonitor()
    @State private var showingTravelModeSheet = false
    @State private var detectedTimeZone: TimeZone?
    @State private var currentLocation: String = "Loading..."
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Status
                    TimeZoneStatusCard(
                        currentTimeZone: timeZoneMonitor.currentTimeZone,
                        homeTimeZone: timeZoneMonitor.homeTimeZone,
                        isTravelModeActive: timeZoneMonitor.isTravelModeActive,
                        location: currentLocation
                    )
                    
                    // Travel Mode Controls
                    if timeZoneMonitor.hasTimeZoneChanged {
                        TravelModePrompt(
                            detectedTimeZone: timeZoneMonitor.currentTimeZone,
                            onEnableTravelMode: {
                                showingTravelModeSheet = true
                            },
                            onDismiss: {
                                timeZoneMonitor.dismissTravelPrompt()
                            }
                        )
                    }
                    
                    // Manual Controls
                    VStack(spacing: 12) {
                        if timeZoneMonitor.isTravelModeActive {
                            Button("Exit Travel Mode") {
                                timeZoneMonitor.exitTravelMode()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Button("Enter Travel Mode") {
                                showingTravelModeSheet = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        
                        Button("Set Home Time Zone") {
                            timeZoneMonitor.setHomeTimeZone()
                        }
                        .buttonStyle(TertiaryButtonStyle())
                    }
                    .padding(.horizontal)
                    
                    // Travel History
                    TravelHistorySection(monitor: timeZoneMonitor)
                }
                .padding()
            }
            .navigationTitle("Time Zone")
            .sheet(isPresented: $showingTravelModeSheet) {
                TravelModeSheet(monitor: timeZoneMonitor)
            }
        }
        .onAppear {
            updateLocationName()
        }
    }
    
    private func updateLocationName() {
        let geocoder = CLGeocoder()
        if let location = timeZoneMonitor.currentLocation {
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                DispatchQueue.main.async {
                    if let placemark = placemarks?.first {
                        if let city = placemark.locality, let state = placemark.administrativeArea {
                            currentLocation = "\(city), \(state)"
                        } else if let country = placemark.country {
                            currentLocation = country
                        } else {
                            currentLocation = "Unknown location"
                        }
                    } else {
                        currentLocation = "Location unavailable"
                    }
                }
            }
        } else {
            currentLocation = "Location unavailable"
        }
    }
}

// MARK: - Time Zone Status Card

struct TimeZoneStatusCard: View {
    let currentTimeZone: TimeZone
    let homeTimeZone: TimeZone?
    let isTravelModeActive: Bool
    let location: String
    
    private var timeZoneOffset: String {
        let formatter = DateFormatter()
        formatter.timeZone = currentTimeZone
        formatter.dateFormat = "ZZZZZ"
        return formatter.string(from: Date())
    }
    
    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = currentTimeZone
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Current Time Zone")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                if isTravelModeActive {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .foregroundColor(.blue)
                        Text("Travel Mode")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            
            // Time Zone Info
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Current Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentTime)
                            .fontWeight(.medium)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Zone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentTimeZone.identifier)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Offset")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timeZoneOffset)
                            .fontWeight(.medium)
                    }
                }
                
                if let homeTimeZone = homeTimeZone, homeTimeZone != currentTimeZone {
                    Divider()
                    
                    HStack {
                        Text("Home Time Zone:")
                            .foregroundColor(.secondary)
                        Text(homeTimeZone.identifier)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        let homeTime = DateFormatter().apply {
                            $0.timeZone = homeTimeZone
                            $0.timeStyle = .short
                        }.string(from: Date())
                        
                        Text("Home time: \(homeTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time zone status. Current location: \(location). Current time: \(currentTime).")
    }
}

// MARK: - Travel Mode Prompt

struct TravelModePrompt: View {
    let detectedTimeZone: TimeZone
    let onEnableTravelMode: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Zone Change Detected")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Detected: \(detectedTimeZone.identifier)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text("Would you like to enable Travel Mode to adjust your dose timing?")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 12) {
                Button("Not Now") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Enable Travel Mode") {
                    onEnableTravelMode()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time zone change detected. Enable travel mode or dismiss.")
    }
}

// MARK: - Travel Mode Sheet

struct TravelModeSheet: View {
    @ObservedObject var monitor: TimeZoneMonitor
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedStartDate = Date()
    @State private var selectedEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var gradualAdjustment = true
    @State private var adjustmentDays = 3
    
    var body: some View {
        NavigationView {
            Form {
                Section("Travel Details") {
                    HStack {
                        Text("From")
                        Spacer()
                        Text(monitor.homeTimeZone?.identifier ?? "Home")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("To")
                        Spacer()
                        Text(monitor.currentTimeZone.identifier)
                            .foregroundColor(.secondary)
                    }
                    
                    DatePicker("Start Date", selection: $selectedStartDate, displayedComponents: .date)
                    
                    DatePicker("End Date", selection: $selectedEndDate, displayedComponents: .date)
                }
                
                Section("Adjustment Method") {
                    Toggle("Gradual adjustment", isOn: $gradualAdjustment)
                    
                    if gradualAdjustment {
                        Stepper("Over \(adjustmentDays) days", value: $adjustmentDays, in: 1...7)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Text(gradualAdjustment 
                         ? "Your dose times will gradually shift over \(adjustmentDays) days to help minimize jet lag effects."
                         : "Your dose times will immediately adjust to the new time zone."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Travel Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Enable") {
                        enableTravelMode()
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .accessibilityLabel("Travel mode configuration. Enable travel mode.")
    }
    
    private func enableTravelMode() {
        monitor.enableTravelMode(
            startDate: selectedStartDate,
            endDate: selectedEndDate,
            gradualAdjustment: gradualAdjustment,
            adjustmentDays: gradualAdjustment ? adjustmentDays : 1
        )
    }
}

// MARK: - Travel History Section

struct TravelHistorySection: View {
    @ObservedObject var monitor: TimeZoneMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Travel")
                .font(.headline)
                .padding(.horizontal)
            
            if monitor.recentTravelHistory.isEmpty {
                Text("No recent travel")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(monitor.recentTravelHistory, id: \.id) { entry in
                    TravelHistoryRow(entry: entry)
                }
            }
        }
    }
}

struct TravelHistoryRow: View {
    let entry: TravelHistoryEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.fromTimeZone)
                        .fontWeight(.medium)
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(entry.toTimeZone)
                        .fontWeight(.medium)
                }
                
                Text(entry.startDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if entry.isActive {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
            } else {
                Text("\(entry.durationDays) days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Button Styles

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif // os(iOS)

// MARK: - Extensions

struct TravelHistoryEntry {
    let id = UUID()
    let fromTimeZone: String
    let toTimeZone: String
    let startDate: Date
    let endDate: Date?
    let isActive: Bool
    
    var durationDays: Int {
        guard let endDate = endDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
}
