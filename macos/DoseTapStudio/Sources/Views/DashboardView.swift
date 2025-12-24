import SwiftUI

/// Main dashboard view showing key metrics and recent activity
struct DashboardView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        let analytics = dataStore.analytics
        let adherenceRate = analytics.adherenceRate30d
        let averageWindow = analytics.averageWindow30d
        let missedDoses = analytics.missedDoses30d
        let avgRecovery = analytics.averageRecovery30d
        let avgHR = analytics.averageHR30d
        
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("DoseTap Analytics Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let folderURL = dataStore.folderURL {
                        Text("Data from: \(folderURL.lastPathComponent)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Key Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                                        // Adherence Card
                    MetricCard(
                        title: "30-Day Adherence",
                        value: String(format: "%.1f%%", adherenceRate),
                        subtitle: analytics.adherenceStatusText,
                        color: getAdherenceColor(adherenceRate),
                        icon: "checkmark.circle.fill"
                    )
                    
                    // Average Window Card
                    MetricCard(
                        title: "Avg Dose Window",
                        value: String(format: "%.0f min", averageWindow),
                        subtitle: getWindowStatusText(averageWindow),
                        color: .blue,
                        icon: "clock.fill"
                    )
                    
                    // Missed Doses Card
                    MetricCard(
                        title: "Missed Doses",
                        value: "\(missedDoses)",
                        subtitle: "Last 30 days",
                        color: missedDoses > 3 ? .red : .green,
                        icon: "exclamationmark.triangle.fill"
                    )
                }
                .padding(.horizontal)
                
                // WHOOP Metrics (if available)
                if let avgRecovery = avgRecovery,
                   let avgHR = avgHR {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        MetricCard(
                            title: "Avg Recovery",
                            value: String(format: "%.0f%%", avgRecovery),
                            subtitle: "WHOOP data",
                            color: .purple,
                            icon: "heart.fill"
                        )
                        
                        MetricCard(
                            title: "Avg Heart Rate",
                            value: String(format: "%.0f bpm", avgHR),
                            subtitle: "During sessions",
                            color: .orange,
                            icon: "waveform.path.ecg"
                        )
                    }
                    .padding(.horizontal)
                }
                
                // Current Inventory Status
                if let inventory = dataStore.currentInventory {
                    InventoryStatusCard(inventory: inventory)
                        .padding(.horizontal)
                }
                
                // Recent Activity
                RecentActivityView(dataStore: dataStore)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
    }
    
    private func getAdherenceColor(_ rate: Double) -> Color {
        switch rate {
        case 95...100: return .green
        case 85..<95: return .blue
        case 70..<85: return .orange
        default: return .red
        }
    }
    
    private func getWindowStatusText(_ averageWindow: Double) -> String {
        switch averageWindow {
        case 150...180: return "Optimal Window"
        case 181...210: return "Good Window"
        case 211...240: return "Late Window"
        default: return averageWindow < 150 ? "Early Window" : "Missed Window"
        }
    }
}

/// Reusable metric card component
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// Current inventory status card
struct InventoryStatusCard: View {
    let inventory: InventorySnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pills.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Current Inventory")
                    .font(.headline)
                
                Spacer()
                
                Text(inventory.asOfUTC, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("\(inventory.bottlesRemaining)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Bottles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("\(inventory.dosesRemaining)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Doses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let daysLeft = inventory.estimatedDaysLeft {
                    VStack(alignment: .leading) {
                        Text("\(daysLeft)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(daysLeft < 7 ? .red : .primary)
                        Text("Days Left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            if let notes = inventory.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// Recent activity summary
struct RecentActivityView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        let recentEvents = Array(dataStore.events.suffix(10).reversed())
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
            
            if recentEvents.isEmpty {
                Text("No recent events")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(recentEvents, id: \.id) { event in
                        HStack {
                            Image(systemName: event.eventType.iconName)
                                .foregroundColor(event.eventType.color)
                                .frame(width: 20)
                            
                            Text(event.eventType.displayName)
                                .font(.body)
                            
                            Spacer()
                            
                            Text(event.occurredAtUTC, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Extensions for UI

extension EventType {
    var iconName: String {
        switch self {
        case .dose1_taken: return "1.circle.fill"
        case .dose2_taken: return "2.circle.fill"
        case .dose2_skipped: return "2.circle"
        case .dose2_snoozed: return "clock.circle"
        case .bathroom: return "drop.circle"
        case .undo: return "arrow.uturn.backward.circle"
        case .snooze: return "clock.circle.fill"
        case .lights_out: return "moon.circle"
        case .wake_final: return "sun.max.circle"
        case .app_opened: return "app.circle"
        case .notification_received: return "bell.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .dose1_taken, .dose2_taken: return .green
        case .dose2_skipped: return .orange
        case .dose2_snoozed: return .blue
        case .bathroom: return .cyan
        case .undo: return .red
        case .snooze: return .blue
        case .lights_out: return .indigo
        case .wake_final: return .yellow
        case .app_opened: return .gray
        case .notification_received: return .purple
        }
    }
    
    var displayName: String {
        switch self {
        case .dose1_taken: return "Dose 1 Taken"
        case .dose2_taken: return "Dose 2 Taken"
        case .dose2_skipped: return "Dose 2 Skipped"
        case .dose2_snoozed: return "Dose 2 Snoozed"
        case .bathroom: return "Bathroom Break"
        case .undo: return "Undo Action"
        case .snooze: return "Snooze"
        case .lights_out: return "Lights Out"
        case .wake_final: return "Final Wake"
        case .app_opened: return "App Opened"
        case .notification_received: return "Notification"
        }
    }
}

#Preview {
    NavigationView {
        DashboardView(dataStore: DataStore())
    }
}
