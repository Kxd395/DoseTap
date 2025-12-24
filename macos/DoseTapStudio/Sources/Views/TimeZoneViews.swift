import SwiftUI

/// Time zone change detection and travel mode management
/// Implements ASCII specifications for time zone handling and schedule adjustments

/// Time zone change detection alert
struct TimeZoneChangeAlert: View {
    let detectedTimeZone: String
    let currentSchedule: String
    let newSchedule: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            scheduleComparison
            actionButtons
        }
        .padding(24)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 500)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Time Zone Changed")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            
            Text("We detected \(detectedTimeZone). Recalculate tonight's window?")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var scheduleComparison: some View {
        VStack(spacing: 16) {
            scheduleRow(
                label: "Current schedule:",
                time: currentSchedule,
                color: .secondary
            )
            
            scheduleRow(
                label: "New timezone:",
                time: newSchedule,
                color: .blue
            )
        }
        .padding()
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func scheduleRow(label: String, time: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(time)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Keep current schedule") {
                handleKeepCurrent()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.controlColor))
            .cornerRadius(8)
            .disabled(isProcessing)
            .accessibilityLabel("Keep current schedule")
            
            Button("Recalculate & Reschedule") {
                handleRecalculate()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isProcessing)
            .accessibilityLabel("Recalculate and reschedule")
        }
    }
    
    private func handleKeepCurrent() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🕐 Keeping current schedule")
            dismiss()
        }
    }
    
    private func handleRecalculate() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🌍 Recalculating for new timezone")
            // Present travel mode confirmation
            NotificationCenter.default.post(name: .showTravelModeConfirmation, object: detectedTimeZone)
            dismiss()
        }
    }
}

/// Travel mode confirmation view
struct TravelModeConfirmation: View {
    let location: String
    let timeZone: String
    let adjustedSchedule: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            scheduleDetails
            actionButtons
        }
        .padding(24)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 500)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Travel Mode Active")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            
            Text("Your schedule has been adjusted for:")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var scheduleDetails: some View {
        VStack(spacing: 16) {
            HStack {
                Text("📍")
                Text(location)
                    .fontWeight(.medium)
                Spacer()
            }
            
            Divider()
            
            VStack(spacing: 8) {
                HStack {
                    Text("Tonight's window:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(adjustedSchedule)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Notifications rescheduled")
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Manual Adjustment") {
                handleManualAdjustment()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.controlColor))
            .cornerRadius(8)
            .disabled(isProcessing)
            .accessibilityLabel("Manual adjustment")
            
            Button("Continue") {
                handleContinue()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isProcessing)
            .accessibilityLabel("Continue with travel mode")
        }
    }
    
    private func handleManualAdjustment() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("⚙️ Opening manual time adjustment")
            dismiss()
        }
    }
    
    private func handleContinue() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("✈️ Travel mode activated for \(location)")
            dismiss()
        }
    }
}

/// Time zone management container view
struct TimeZoneManagementView: View {
    @State private var showTimeZoneAlert = false
    @State private var showTravelConfirmation = false
    @State private var detectedTimeZone = "Europe/Paris"
    @State private var currentTimeZone = TimeZone.current.identifier
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Time Zone Management")
                    .font(.title)
                    .fontWeight(.bold)
                
                currentTimeZoneSection
                
                simulationControls
                
                Spacer()
            }
            .padding()
            .navigationTitle("Travel & Time Zones")
        }
        .sheet(isPresented: $showTimeZoneAlert) {
            timeZoneChangeSheet
        }
        .sheet(isPresented: $showTravelConfirmation) {
            travelConfirmationSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTravelModeConfirmation)) { notification in
            if let timeZone = notification.object as? String {
                detectedTimeZone = timeZone
                showTravelConfirmation = true
            }
        }
    }
    
    private var currentTimeZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Settings")
                .font(.headline)
            
            HStack {
                Text("Time Zone:")
                Spacer()
                Text(currentTimeZone)
                    .foregroundColor(.blue)
            }
            
            HStack {
                Text("Auto-detect changes:")
                Spacer()
                Text("ON")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var simulationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulation Controls")
                .font(.headline)
            
            Button("Simulate Europe/Paris Detection") {
                detectedTimeZone = "Europe/Paris"
                showTimeZoneAlert = true
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Button("Simulate Asia/Tokyo Detection") {
                detectedTimeZone = "Asia/Tokyo"
                showTimeZoneAlert = true
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var timeZoneChangeSheet: some View {
        TimeZoneChangeAlert(
            detectedTimeZone: detectedTimeZone,
            currentSchedule: "01:00 AM → 165m window",
            newSchedule: timeZoneSchedule(for: detectedTimeZone)
        )
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    private var travelConfirmationSheet: some View {
        TravelModeConfirmation(
            location: locationName(for: detectedTimeZone),
            timeZone: detectedTimeZone,
            adjustedSchedule: "07:00 AM → 09:45 AM (165m)"
        )
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    private func timeZoneSchedule(for timeZone: String) -> String {
        switch timeZone {
        case "Europe/Paris":
            return "07:00 AM → 165m window"
        case "Asia/Tokyo":
            return "02:00 PM → 165m window"
        default:
            return "Adjusted time → 165m window"
        }
    }
    
    private func locationName(for timeZone: String) -> String {
        switch timeZone {
        case "Europe/Paris":
            return "Paris, France (UTC+1)"
        case "Asia/Tokyo":
            return "Tokyo, Japan (UTC+9)"
        default:
            return "Unknown Location"
        }
    }
}

/// Notification extensions for travel mode
extension Notification.Name {
    static let showTravelModeConfirmation = Notification.Name("showTravelModeConfirmation")
}

#Preview("Time Zone Change Alert") {
    TimeZoneChangeAlert(
        detectedTimeZone: "Europe/Paris",
        currentSchedule: "01:00 AM → 165m window",
        newSchedule: "07:00 AM → 165m window"
    )
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Travel Mode Confirmation") {
    TravelModeConfirmation(
        location: "Paris, France (UTC+1)",
        timeZone: "Europe/Paris",
        adjustedSchedule: "07:00 AM → 09:45 AM (165m)"
    )
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Time Zone Management") {
    TimeZoneManagementView()
}
