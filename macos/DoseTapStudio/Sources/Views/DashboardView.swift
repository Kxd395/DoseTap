import SwiftUI
import Charts

/// Main dashboard view showing key metrics and recent activity
struct DashboardView: View {
    @ObservedObject var dataStore: DataStore
    @State private var trendMode: DashboardTrendMode = .intervalVsQuality
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DashboardHeader(dataStore: dataStore)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 180)),
                        GridItem(.flexible(minimum: 180)),
                        GridItem(.flexible(minimum: 180))
                    ],
                    spacing: 12
                ) {
                    DashboardSummaryCard(analytics: dataStore.analytics)
                        .gridCellColumns(3)

                    MetricCard(
                        title: "30-Day Adherence",
                        value: String(format: "%.1f%%", dataStore.analytics.adherenceRate30d),
                        subtitle: dataStore.analytics.adherenceStatusText,
                        color: getAdherenceColor(dataStore.analytics.adherenceRate30d),
                        icon: "checkmark.circle.fill"
                    )
                    MetricCard(
                        title: "Avg Dose Window",
                        value: String(format: "%.0f min", dataStore.analytics.averageWindow30d),
                        subtitle: dataStore.analytics.windowStatusText,
                        color: .blue,
                        icon: "clock.fill"
                    )
                    MetricCard(
                        title: "Missed Doses",
                        value: "\(dataStore.analytics.missedDoses30d)",
                        subtitle: "Last 30 days",
                        color: dataStore.analytics.missedDoses30d > 3 ? .red : .green,
                        icon: "exclamationmark.triangle.fill"
                    )

                    MetricCard(
                        title: "Avg Sleep Efficiency",
                        value: dataStore.analytics.averageSleepEfficiency30d
                            .map { String(format: "%.1f%%", $0) } ?? "No data",
                        subtitle: "Imported sessions",
                        color: .indigo,
                        icon: "moon.zzz.fill"
                    )
                    MetricCard(
                        title: "Quality Issue Nights",
                        value: "\(dataStore.analytics.qualityIssueNights30d)",
                        subtitle: "Duplicate/missing-night flags",
                        color: .orange,
                        icon: "exclamationmark.shield.fill"
                    )
                    MetricCard(
                        title: "High Confidence Nights",
                        value: "\(dataStore.analytics.highConfidenceNights30d)",
                        subtitle: "Completeness >= 70%",
                        color: .green,
                        icon: "checkmark.seal.fill"
                    )

                    if let avgRecovery = dataStore.analytics.averageRecovery30d {
                        MetricCard(
                            title: "Avg Recovery",
                            value: String(format: "%.0f%%", avgRecovery),
                            subtitle: "WHOOP imported values",
                            color: .purple,
                            icon: "heart.fill"
                        )
                    }

                    if let avgHR = dataStore.analytics.averageHR30d {
                        MetricCard(
                            title: "Avg Heart Rate",
                            value: String(format: "%.0f bpm", avgHR),
                            subtitle: "Session average HR",
                            color: .pink,
                            icon: "waveform.path.ecg"
                        )
                    }
                }

                DashboardRecentNightsTable(nights: dataStore.analytics.nights)

                DashboardTrendChartsPanel(nights: dataStore.analytics.nights, trendMode: $trendMode)

                DashboardIntegrationsPanel(analytics: dataStore.analytics)

                if let inventory = dataStore.currentInventory {
                    InventoryStatusCard(inventory: inventory)
                }

                RecentActivityView(dataStore: dataStore)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
}

private enum DashboardTrendMode: String, CaseIterable, Identifiable {
    case intervalVsQuality = "Interval vs Quality"
    case weekdayAdherence = "Weekday Adherence"

    var id: String { rawValue }
}

private struct DashboardHeader: View {
    @ObservedObject var dataStore: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DoseTap Analytics Dashboard")
                .font(.largeTitle.bold())
            if let folderURL = dataStore.folderURL {
                Text("Data source: \(folderURL.lastPathComponent)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let lastImported = dataStore.lastImported {
                Text("Last import: \(lastImported.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardSummaryCard: View {
    let analytics: DoseTapAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operational Summary")
                .font(.headline)
            Text("Sessions: \(analytics.totalSessions) • Events: \(analytics.totalEvents)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Avg events per night: \(String(format: "%.1f", analytics.averageEventsPerNight30d))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("This dashboard uses nightly aggregates to keep dosing, events, and recovery metrics aligned.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
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

private struct DashboardRecentNightsTable: View {
    let nights: [StudioNightAggregate]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Night Aggregates")
                .font(.headline)

            if nights.isEmpty {
                Text("No nightly aggregates in the selected data range.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Night").font(.caption.bold())
                        Text("Interval").font(.caption.bold())
                        Text("On-Time").font(.caption.bold())
                        Text("Events").font(.caption.bold())
                        Text("Quality").font(.caption.bold())
                    }

                    ForEach(nights.prefix(12)) { night in
                        GridRow {
                            Text(night.id).font(.caption)
                            Text(intervalText(for: night)).font(.caption)
                            Text(onTimeText(for: night))
                                .font(.caption)
                                .foregroundColor(onTimeColor(for: night))
                            Text("\(night.eventCount)").font(.caption)
                            Text("\(Int((night.completenessScore * 100).rounded()))%")
                                .font(.caption)
                                .foregroundColor(night.completenessScore >= 0.7 ? .green : .orange)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func intervalText(for night: StudioNightAggregate) -> String {
        if night.dose2Skipped {
            return "Skipped"
        }
        guard let minutes = night.intervalMinutes else { return "No interval" }
        return "\(minutes)m"
    }

    private func onTimeText(for night: StudioNightAggregate) -> String {
        guard let onTime = night.onTimeFlag else { return "N/A" }
        return onTime ? "Yes" : "No"
    }

    private func onTimeColor(for night: StudioNightAggregate) -> Color {
        guard let onTime = night.onTimeFlag else { return .secondary }
        return onTime ? .green : .orange
    }
}

private struct DashboardTrendChartsPanel: View {
    let nights: [StudioNightAggregate]
    @Binding var trendMode: DashboardTrendMode

    private struct XYPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let onTime: Bool
    }

    private struct NamedValue: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
    }

    private var intervalVsQualityPoints: [XYPoint] {
        nights.compactMap { night in
            guard let interval = night.intervalMinutes, let efficiency = night.sleepEfficiency else { return nil }
            return XYPoint(x: Double(interval), y: efficiency, onTime: night.onTimeFlag ?? false)
        }
    }

    private var weekdayAdherenceValues: [NamedValue] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        var buckets: [Int: [Bool]] = [:]
        for night in nights {
            guard let onTime = night.onTimeFlag, let date = formatter.date(from: night.id) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            buckets[weekday, default: []].append(onTime)
        }
        return (1...7).map { weekday in
            let values = buckets[weekday] ?? []
            let rate = values.isEmpty ? 0 : (Double(values.filter { $0 }.count) / Double(values.count)) * 100
            return NamedValue(name: symbols[weekday - 1], value: rate)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Interactive Trends")
                    .font(.headline)
                Spacer()
                Picker("Trend", selection: $trendMode) {
                    ForEach(DashboardTrendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            switch trendMode {
            case .intervalVsQuality:
                if intervalVsQualityPoints.isEmpty {
                    emptyState("Need interval + sleep efficiency values to plot this trend.")
                } else {
                    Chart(intervalVsQualityPoints) { point in
                        PointMark(
                            x: .value("Interval (min)", point.x),
                            y: .value("Sleep Efficiency %", point.y)
                        )
                        .foregroundStyle(point.onTime ? .green : .orange)
                    }
                    .frame(height: 220)
                }

            case .weekdayAdherence:
                if weekdayAdherenceValues.allSatisfy({ $0.value == 0 }) {
                    emptyState("Need completed dose intervals to compute weekday adherence.")
                } else {
                    Chart(weekdayAdherenceValues) { entry in
                        BarMark(
                            x: .value("Weekday", entry.name),
                            y: .value("On-Time %", entry.value)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 220)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct DashboardIntegrationsPanel: View {
    let analytics: DoseTapAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Integration Readiness")
                .font(.headline)

            integrationRow(
                name: "WHOOP",
                status: analytics.averageRecovery30d != nil ? "Imported" : "Not present",
                detail: analytics.averageRecovery30d != nil
                    ? "Recovery/HR metrics are flowing in imported sessions."
                    : "Import WHOOP-enriched sessions to unlock recovery views.",
                color: analytics.averageRecovery30d != nil ? .green : .orange
            )

            integrationRow(
                name: "Apple Health",
                status: analytics.averageSleepEfficiency30d != nil ? "Imported" : "Not present",
                detail: analytics.averageSleepEfficiency30d != nil
                    ? "Sleep efficiency fields are available for trend analysis."
                    : "Import sessions with sleep efficiency to power sleep quality tiles.",
                color: analytics.averageSleepEfficiency30d != nil ? .green : .orange
            )

            integrationRow(
                name: "Cloud Sync",
                status: "Planned",
                detail: "Nightly aggregate model is ready to map into CloudKit records.",
                color: .blue
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func integrationRow(name: String, status: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.subheadline.bold())
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundColor(color)
            }
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
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
