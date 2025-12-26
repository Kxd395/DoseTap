import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var dataStorage = DataStorageService.shared
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showingExport = false
    
    @MainActor
    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"
        case all = "All Time"
        
        var dateRange: (start: Date, end: Date) {
            let end = Date()
            let calendar = Calendar.current
            let start: Date
            
            switch self {
            case .week:
                start = calendar.date(byAdding: .day, value: -7, to: end)!
            case .month:
                start = calendar.date(byAdding: .day, value: -30, to: end)!
            case .quarter:
                start = calendar.date(byAdding: .day, value: -90, to: end)!
            case .all:
                start = DataStorageService.shared.getAllSessions().last?.startTime ?? calendar.date(byAdding: .year, value: -1, to: end)!
            }
            
            return (start, end)
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Time Range Picker
                    TimeRangePicker(selectedRange: $selectedTimeRange)
                    
                    // Current Session Card
                    if let currentSession = dataStorage.currentSession {
                        CurrentSessionCard(session: currentSession)
                    }
                    
                    // Key Metrics Overview
                    MetricsOverviewCard(timeRange: selectedTimeRange)
                    
                    // Dose Timing Chart
                    DoseTimingChart(timeRange: selectedTimeRange)
                    
                    // Sleep Data Integration
                    SleepDataCard(timeRange: selectedTimeRange)
                    
                    // Recent Events
                    RecentEventsCard()
                    
                    // Adherence Analysis
                    AdherenceCard(timeRange: selectedTimeRange)
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingExport = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(items: [dataStorage.exportToCSV()])
        }
    }
}

struct TimeRangePicker: View {
    @Binding var selectedRange: DashboardView.TimeRange
    
    var body: some View {
        Picker("Time Range", selection: $selectedRange) {
            ForEach(DashboardView.TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

struct CurrentSessionCard: View {
    let session: DoseSessionData
    
    private var dose1Time: Date? {
        session.events.first { $0.type == .dose1 }?.timestamp
    }
    
    private var dose2Time: Date? {
        session.events.first { $0.type == .dose2 }?.timestamp
    }
    
    private var intervalDuration: TimeInterval? {
        guard let d1 = dose1Time, let d2 = dose2Time else { return nil }
        return d2.timeIntervalSince(d1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Session")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if dose2Time != nil {
                    Text("Completed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                } else {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }
            
            if let d1 = dose1Time {
                HStack {
                    Text("Dose 1:")
                    Spacer()
                    Text(d1, style: .time)
                        .foregroundColor(.secondary)
                }
                
                if let d2 = dose2Time, let interval = intervalDuration {
                    HStack {
                        Text("Dose 2:")
                        Spacer()
                        Text(d2, style: .time)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Interval:")
                        Spacer()
                        Text(formatDuration(interval))
                            .foregroundColor(intervalColor(interval))
                            .fontWeight(.medium)
                    }
                } else {
                    HStack {
                        Text("Next dose window:")
                        Spacer()
                        Text("2.5-4 hours")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No dose events in current session")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func intervalColor(_ duration: TimeInterval) -> Color {
        let minutes = duration / 60
        if minutes >= 150 && minutes <= 240 {
            return .green
        } else if minutes >= 120 && minutes < 150 {
            return .orange
        } else {
            return .red
        }
    }
}

struct MetricsOverviewCard: View {
    @StateObject private var dataStorage = DataStorageService.shared
    let timeRange: DashboardView.TimeRange
    
    private var sessions: [DoseSessionData] {
        let range = timeRange.dateRange
        return dataStorage.getSessionsInDateRange(start: range.start, end: range.end)
    }
    
    private var completedSessions: [DoseSessionData] {
        sessions.filter { $0.endTime != nil }
    }
    
    private var averageInterval: TimeInterval? {
        let intervals = completedSessions.compactMap { session -> TimeInterval? in
            guard let dose1 = session.events.first(where: { $0.type == .dose1 }),
                  let dose2 = session.events.first(where: { $0.type == .dose2 }) else { return nil }
            return dose2.timestamp.timeIntervalSince(dose1.timestamp)
        }
        
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }
    
    private var onTimePercentage: Double {
        let intervals = completedSessions.compactMap { session -> TimeInterval? in
            guard let dose1 = session.events.first(where: { $0.type == .dose1 }),
                  let dose2 = session.events.first(where: { $0.type == .dose2 }) else { return nil }
            return dose2.timestamp.timeIntervalSince(dose1.timestamp)
        }
        
        guard !intervals.isEmpty else { return 0 }
        let onTimeCount = intervals.filter { interval in
            let minutes = interval / 60
            return minutes >= 150 && minutes <= 240
        }.count
        
        return Double(onTimeCount) / Double(intervals.count) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Metrics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                MetricTile(
                    title: "Sessions",
                    value: "\(completedSessions.count)",
                    subtitle: timeRange.rawValue,
                    color: .blue
                )
                
                MetricTile(
                    title: "Avg Interval",
                    value: averageInterval != nil ? formatDuration(averageInterval!) : "N/A",
                    subtitle: "Time between doses",
                    color: .green
                )
                
                MetricTile(
                    title: "On-Time Rate",
                    value: String(format: "%.0f%%", onTimePercentage),
                    subtitle: "Within 2.5-4h window",
                    color: onTimePercentage >= 80 ? .green : onTimePercentage >= 60 ? .orange : .red
                )
                
                MetricTile(
                    title: "Total Events",
                    value: "\(sessions.flatMap { $0.events }.count)",
                    subtitle: "All logged events",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct DoseTimingChart: View {
    @StateObject private var dataStorage = DataStorageService.shared
    let timeRange: DashboardView.TimeRange
    
    private var chartData: [DoseIntervalData] {
        let range = timeRange.dateRange
        let sessions = dataStorage.getSessionsInDateRange(start: range.start, end: range.end)
        
        return sessions.compactMap { session in
            guard let dose1 = session.events.first(where: { $0.type == .dose1 }),
                  let dose2 = session.events.first(where: { $0.type == .dose2 }) else { return nil }
            
            let interval = dose2.timestamp.timeIntervalSince(dose1.timestamp) / 60 // Convert to minutes
            return DoseIntervalData(date: dose1.timestamp, intervalMinutes: interval)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Timing Trends")
                .font(.headline)
            
            if !chartData.isEmpty {
                Chart(chartData) { data in
                    LineMark(
                        x: .value("Date", data.date),
                        y: .value("Interval (min)", data.intervalMinutes)
                    )
                    .foregroundStyle(colorForInterval(data.intervalMinutes))
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            Text("\(Int(value.as(Double.self) ?? 0))m")
                        }
                    }
                }
                .chartYScale(domain: 120...280)
                .overlay(
                    Rectangle()
                        .fill(Color.green.opacity(0.1))
                        .frame(height: 200 * (240 - 150) / (280 - 120))
                        .offset(y: 200 * (280 - 240) / (280 - 120))
                        .allowsHitTesting(false)
                )
            } else {
                VStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No dose timing data")
                        .foregroundColor(.secondary)
                }
                .frame(height: 150)
            }
            
            Text("Green zone: 2.5-4 hour optimal window")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func colorForInterval(_ minutes: Double) -> Color {
        if minutes >= 150 && minutes <= 240 {
            return .green
        } else if minutes >= 120 && minutes < 150 {
            return .orange
        } else {
            return .red
        }
    }
}

struct DoseIntervalData: Identifiable {
    let id = UUID()
    let date: Date
    let intervalMinutes: Double
}

struct SleepDataCard: View {
    let timeRange: DashboardView.TimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Data Integration")
                .font(.headline)
            
            VStack(spacing: 12) {
                SleepDataRow(
                    title: "Apple Health",
                    status: "Connected",
                    lastSync: "2 hours ago",
                    statusColor: .green
                )
                
                SleepDataRow(
                    title: "WHOOP",
                    status: "Not Connected",
                    lastSync: "Never",
                    statusColor: .orange
                )
            }
            
            Button("Configure Health Integrations") {
                // TODO: Navigate to health settings
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SleepDataRow: View {
    let title: String
    let status: String
    let lastSync: String
    let statusColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Last sync: \(lastSync)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(status)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct RecentEventsCard: View {
    @StateObject private var dataStorage = DataStorageService.shared
    
    private var recentEvents: [DoseEvent] {
        dataStorage.getRecentEvents(limit: 5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Events")
                    .font(.headline)
                Spacer()
                NavigationLink("View All") {
                    EventHistoryView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if recentEvents.isEmpty {
                VStack {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No recent events")
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentEvents) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EventRow: View {
    let event: DoseEvent
    
    var body: some View {
        HStack {
            Image(systemName: iconForEventType(event.type))
                .foregroundColor(colorForEventType(event.type))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(event.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func iconForEventType(_ type: DoseEventType) -> String {
        switch type {
        case .dose1: return "1.circle.fill"
        case .dose2: return "2.circle.fill"
        case .snooze: return "clock.fill"
        case .skip: return "xmark.circle.fill"
        case .bathroom: return "figure.walk"
        case .lightsOut: return "moon.fill"
        case .wakeFinal: return "sun.max.fill"
        }
    }
    
    private func colorForEventType(_ type: DoseEventType) -> Color {
        switch type {
        case .dose1: return .blue
        case .dose2: return .green
        case .snooze: return .orange
        case .skip: return .red
        case .bathroom: return .purple
        case .lightsOut: return .indigo
        case .wakeFinal: return .yellow
        }
    }
}

struct AdherenceCard: View {
    @StateObject private var dataStorage = DataStorageService.shared
    let timeRange: DashboardView.TimeRange
    
    private var adherenceData: (onTime: Int, early: Int, late: Int, missed: Int) {
        let range = timeRange.dateRange
        let sessions = dataStorage.getSessionsInDateRange(start: range.start, end: range.end)
        
        var onTime = 0
        var early = 0
        var late = 0
        var missed = 0
        
        for session in sessions {
            guard let dose1 = session.events.first(where: { $0.type == .dose1 }) else {
                missed += 1
                continue
            }
            
            guard let dose2 = session.events.first(where: { $0.type == .dose2 }) else {
                missed += 1
                continue
            }
            
            let intervalMinutes = dose2.timestamp.timeIntervalSince(dose1.timestamp) / 60
            
            if intervalMinutes >= 150 && intervalMinutes <= 240 {
                onTime += 1
            } else if intervalMinutes < 150 {
                early += 1
            } else {
                late += 1
            }
        }
        
        return (onTime, early, late, missed)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adherence Analysis")
                .font(.headline)
            
            let data = adherenceData
            let total = data.onTime + data.early + data.late + data.missed
            
            if total > 0 {
                VStack(spacing: 8) {
                    AdherenceBar(
                        label: "On Time",
                        count: data.onTime,
                        total: total,
                        color: .green
                    )
                    
                    AdherenceBar(
                        label: "Early",
                        count: data.early,
                        total: total,
                        color: .orange
                    )
                    
                    AdherenceBar(
                        label: "Late",
                        count: data.late,
                        total: total,
                        color: .red
                    )
                    
                    AdherenceBar(
                        label: "Missed",
                        count: data.missed,
                        total: total,
                        color: .gray
                    )
                }
            } else {
                Text("No adherence data available")
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct AdherenceBar: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

struct EventHistoryView: View {
    @StateObject private var dataStorage = DataStorageService.shared
    
    var body: some View {
        List {
            ForEach(dataStorage.getAllSessions()) { session in
                Section(header: Text("Session \(session.startTime, style: .date)")) {
                    ForEach(session.events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Event History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DashboardView()
}
