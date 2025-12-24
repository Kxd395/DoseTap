import Foundation
import SwiftUI

// MARK: - Comprehensive Data Export Service
@MainActor
public class DataExportService: ObservableObject {
    public static let shared = DataExportService()
    
    @Published public var isExporting = false
    @Published public var exportProgress: Double = 0.0
    
    private init() {}
    
    // MARK: - Export Formats
    public enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case combined = "Combined Report"
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            case .combined: return "html"
            }
        }
    }
    
    // MARK: - Export Options
    public struct ExportOptions {
        let format: ExportFormat
        let includeDoseEvents: Bool
        let includeHealthData: Bool
        let includeWHOOPData: Bool
        let dateRange: DateRange?
        let includeAnalytics: Bool
        
        public init(format: ExportFormat = .csv,
                   includeDoseEvents: Bool = true,
                   includeHealthData: Bool = true,
                   includeWHOOPData: Bool = true,
                   dateRange: DateRange? = nil,
                   includeAnalytics: Bool = true) {
            self.format = format
            self.includeDoseEvents = includeDoseEvents
            self.includeHealthData = includeHealthData
            self.includeWHOOPData = includeWHOOPData
            self.dateRange = dateRange
            self.includeAnalytics = includeAnalytics
        }
    }
    
    public struct DateRange {
        let start: Date
        let end: Date
    }
    
    // MARK: - Main Export Function
    public func exportData(options: ExportOptions) async -> ExportResult {
        isExporting = true
        exportProgress = 0.0
        
        defer {
            isExporting = false
            exportProgress = 0.0
        }
        
        do {
            let exportData = await gatherExportData(options: options)
            exportProgress = 0.5
            
            let content = try generateExportContent(data: exportData, format: options.format)
            exportProgress = 0.9
            
            let filename = generateFilename(format: options.format)
            exportProgress = 1.0
            
            return .success(content: content, filename: filename, format: options.format)
        } catch {
            return .failure(error: error)
        }
    }
    
    // MARK: - Data Gathering
    private func gatherExportData(options: ExportOptions) async -> ComprehensiveExportData {
        var sessions: [DoseSessionData] = []
        var healthData: [HealthSleepData] = []
        var whoopData: [WHOOPSleepData] = []
        
        // Get dose sessions
        if options.includeDoseEvents {
            if let dateRange = options.dateRange {
                sessions = DataStorageService.shared.getSessionsInDateRange(
                    start: dateRange.start,
                    end: dateRange.end
                )
            } else {
                sessions = DataStorageService.shared.getAllSessions()
            }
        }
        
        // Get health data
        if options.includeHealthData {
            healthData = HealthDataService.shared.recentSleepData
            if let dateRange = options.dateRange {
                healthData = healthData.filter { data in
                    data.sleepDate >= dateRange.start && data.sleepDate <= dateRange.end
                }
            }
        }
        
        // Get WHOOP data
        if options.includeWHOOPData {
            whoopData = WHOOPDataService.shared.recentWHOOPData
            if let dateRange = options.dateRange {
                whoopData = whoopData.filter { data in
                    data.sleepDate >= dateRange.start && data.sleepDate <= dateRange.end
                }
            }
        }
        
        return ComprehensiveExportData(
            sessions: sessions,
            healthData: healthData,
            whoopData: whoopData,
            analytics: options.includeAnalytics ? generateAnalytics(sessions: sessions) : nil,
            exportDate: Date(),
            exportOptions: options
        )
    }
    
    // MARK: - Content Generation
    private func generateExportContent(data: ComprehensiveExportData, format: ExportFormat) throws -> String {
        switch format {
        case .csv:
            return generateCSVContent(data: data)
        case .json:
            return try generateJSONContent(data: data)
        case .combined:
            return generateHTMLReport(data: data)
        }
    }
    
    // MARK: - CSV Export
    private func generateCSVContent(data: ComprehensiveExportData) -> String {
        var csv = "Export Type,Session ID,Event ID,Date,Time,Event Type,Duration,Sleep Start,Sleep End,Sleep Score,Recovery Score,HRV,Strain,Notes\n"
        
        // Dose events
        for session in data.sessions {
            for event in session.events {
                let sessionId = session.sessionId.uuidString.prefix(8)
                let eventId = event.id.uuidString.prefix(8)
                let date = ISO8601DateFormatter().string(from: event.timestamp).prefix(10)
                let time = formatTime(event.timestamp)
                let eventType = event.type.rawValue
                
                // Calculate duration for dose intervals
                let duration: String
                if event.type == .dose2,
                   let dose1 = session.events.first(where: { $0.type == .dose1 }) {
                    let interval = event.timestamp.timeIntervalSince(dose1.timestamp)
                    duration = formatDurationMinutes(interval)
                } else {
                    duration = ""
                }
                
                // Find corresponding sleep data
                let sleepData = findCorrespondingSleepData(for: event.timestamp, in: data)
                
                csv += "Dose Event,\(sessionId),\(eventId),\(date),\(time),\(eventType),\(duration),\(sleepData.sleepStart),\(sleepData.sleepEnd),\(sleepData.sleepScore),\(sleepData.recoveryScore),\(sleepData.hrv),\(sleepData.strain),\(formatMetadata(event.metadata))\n"
            }
        }
        
        // Health data entries
        for health in data.healthData {
            let date = ISO8601DateFormatter().string(from: health.sleepDate).prefix(10)
            let sleepStart = health.sleepStart != nil ? formatTime(health.sleepStart!) : ""
            let sleepEnd = health.sleepEnd != nil ? formatTime(health.sleepEnd!) : ""
            let totalSleep = health.totalSleepTime != nil ? formatDurationMinutes(health.totalSleepTime!) : ""
            let deepSleep = health.deepSleepTime != nil ? formatDurationMinutes(health.deepSleepTime!) : ""
            let remSleep = health.remSleepTime != nil ? formatDurationMinutes(health.remSleepTime!) : ""
            
            csv += "Health Data,,\(health.id.uuidString.prefix(8)),\(date),,Sleep Analysis,\(totalSleep),\(sleepStart),\(sleepEnd),,,,,\"Deep: \(deepSleep), REM: \(remSleep)\"\n"
        }
        
        // WHOOP data entries
        for whoop in data.whoopData {
            let date = ISO8601DateFormatter().string(from: whoop.sleepDate).prefix(10)
            let sleepStart = whoop.sleepStart != nil ? formatTime(whoop.sleepStart!) : ""
            let sleepEnd = whoop.sleepEnd != nil ? formatTime(whoop.sleepEnd!) : ""
            let sleepScore = whoop.sleepScore?.description ?? ""
            let recoveryScore = whoop.recoveryScore?.description ?? ""
            let hrv = whoop.hrv?.description ?? ""
            let strain = whoop.strain?.description ?? ""
            
            csv += "WHOOP Data,,\(whoop.id.uuidString.prefix(8)),\(date),,Sleep Cycle,,\(sleepStart),\(sleepEnd),\(sleepScore),\(recoveryScore),\(hrv),\(strain),\"Cycle: \(whoop.cycleId ?? "N/A")\"\n"
        }
        
        return csv
    }
    
    // MARK: - JSON Export
    private func generateJSONContent(data: ComprehensiveExportData) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(data)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }
    
    // MARK: - HTML Report Export
    private func generateHTMLReport(data: ComprehensiveExportData) -> String {
        let analytics = data.analytics
        
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>DoseTap Comprehensive Report</title>
            <style>
                body { font-family: -apple-system, system-ui, sans-serif; margin: 40px; background: #f5f5f7; }
                .container { max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }
                h1 { color: #1d1d1f; font-size: 2.5rem; margin-bottom: 10px; }
                h2 { color: #1d1d1f; font-size: 1.8rem; margin-top: 40px; margin-bottom: 20px; border-bottom: 2px solid #007aff; padding-bottom: 10px; }
                h3 { color: #424245; font-size: 1.3rem; margin-top: 30px; margin-bottom: 15px; }
                .summary { background: linear-gradient(135deg, #007aff, #5856d6); color: white; padding: 30px; border-radius: 12px; margin: 30px 0; }
                .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
                .metric { background: #f9f9f9; padding: 20px; border-radius: 8px; text-align: center; }
                .metric-value { font-size: 2rem; font-weight: bold; color: #007aff; }
                .metric-label { font-size: 0.9rem; color: #666; margin-top: 5px; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background: #f9f9f9; font-weight: 600; }
                .status-good { color: #34c759; font-weight: bold; }
                .status-warning { color: #ff9500; font-weight: bold; }
                .status-poor { color: #ff3b30; font-weight: bold; }
                .footer { margin-top: 50px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.9rem; color: #666; text-align: center; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>DoseTap Comprehensive Report</h1>
                <p>Generated on \(formatDateTime(data.exportDate))</p>
                
                <div class="summary">
                    <h3 style="margin-top: 0; color: white;">Executive Summary</h3>
                    <p>This report contains \(data.sessions.count) dose sessions, \(data.healthData.count) health data points, and \(data.whoopData.count) WHOOP data points.</p>
                </div>
                
                \(analytics != nil ? generateAnalyticsHTML(analytics!) : "")
                
                <h2>Dose Sessions</h2>
                \(generateSessionsHTML(data.sessions))
                
                \(data.healthData.isEmpty ? "" : generateHealthDataHTML(data.healthData))
                
                \(data.whoopData.isEmpty ? "" : generateWHOOPDataHTML(data.whoopData))
                
                <div class="footer">
                    <p>Generated by DoseTap - XYWAV Dose Timing Assistant</p>
                    <p>This report contains personal health information. Keep confidential.</p>
                </div>
            </div>
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - Analytics Generation
    private func generateAnalytics(sessions: [DoseSessionData]) -> AnalyticsData {
        let completedSessions = sessions.filter { $0.endTime != nil }
        
        let intervals = completedSessions.compactMap { session -> TimeInterval? in
            guard let dose1 = session.events.first(where: { $0.type == .dose1 }),
                  let dose2 = session.events.first(where: { $0.type == .dose2 }) else { return nil }
            return dose2.timestamp.timeIntervalSince(dose1.timestamp)
        }
        
        let avgInterval = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        
        let onTimeCount = intervals.filter { interval in
            let minutes = interval / 60
            return minutes >= 150 && minutes <= 240
        }.count
        
        let adherenceRate = intervals.isEmpty ? 0 : Double(onTimeCount) / Double(intervals.count) * 100
        
        let totalEvents = sessions.flatMap { $0.events }.count
        let snoozeCount = sessions.flatMap { $0.events }.filter { $0.type == .snooze }.count
        let bathroomCount = sessions.flatMap { $0.events }.filter { $0.type == .bathroom }.count
        
        return AnalyticsData(
            totalSessions: sessions.count,
            completedSessions: completedSessions.count,
            averageInterval: avgInterval,
            adherenceRate: adherenceRate,
            totalEvents: totalEvents,
            snoozeCount: snoozeCount,
            bathroomCount: bathroomCount,
            intervalDistribution: calculateIntervalDistribution(intervals)
        )
    }
    
    private func calculateIntervalDistribution(_ intervals: [TimeInterval]) -> [String: Int] {
        var distribution: [String: Int] = [:]
        
        for interval in intervals {
            let minutes = interval / 60
            let range: String
            
            if minutes < 120 {
                range = "< 2h"
            } else if minutes < 150 {
                range = "2-2.5h"
            } else if minutes <= 240 {
                range = "2.5-4h (Optimal)"
            } else if minutes <= 300 {
                range = "4-5h"
            } else {
                range = "> 5h"
            }
            
            distribution[range, default: 0] += 1
        }
        
        return distribution
    }
    
    // MARK: - Helper Functions
    private func generateFilename(format: ExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateString = dateFormatter.string(from: Date())
        return "DoseTap_Export_\(dateString).\(format.fileExtension)"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDurationMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes)"
    }
    
    private func formatMetadata(_ metadata: [String: String]) -> String {
        return metadata.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
    }
    
    private func findCorrespondingSleepData(for date: Date, in data: ComprehensiveExportData) -> (sleepStart: String, sleepEnd: String, sleepScore: String, recoveryScore: String, hrv: String, strain: String) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Try WHOOP data first
        if let whoop = data.whoopData.first(where: { calendar.startOfDay(for: $0.sleepDate) == targetDate }) {
            return (
                sleepStart: whoop.sleepStart != nil ? formatTime(whoop.sleepStart!) : "",
                sleepEnd: whoop.sleepEnd != nil ? formatTime(whoop.sleepEnd!) : "",
                sleepScore: whoop.sleepScore?.description ?? "",
                recoveryScore: whoop.recoveryScore?.description ?? "",
                hrv: whoop.hrv?.description ?? "",
                strain: whoop.strain?.description ?? ""
            )
        }
        
        // Fall back to health data
        if let health = data.healthData.first(where: { calendar.startOfDay(for: $0.sleepDate) == targetDate }) {
            return (
                sleepStart: health.sleepStart != nil ? formatTime(health.sleepStart!) : "",
                sleepEnd: health.sleepEnd != nil ? formatTime(health.sleepEnd!) : "",
                sleepScore: "",
                recoveryScore: "",
                hrv: "",
                strain: ""
            )
        }
        
        return ("", "", "", "", "", "")
    }
    
    private func generateAnalyticsHTML(_ analytics: AnalyticsData) -> String {
        return """
        <h2>Analytics Overview</h2>
        <div class="metrics">
            <div class="metric">
                <div class="metric-value">\(analytics.totalSessions)</div>
                <div class="metric-label">Total Sessions</div>
            </div>
            <div class="metric">
                <div class="metric-value">\(String(format: "%.1f", analytics.averageInterval / 3600))h</div>
                <div class="metric-label">Average Interval</div>
            </div>
            <div class="metric">
                <div class="metric-value">\(String(format: "%.0f", analytics.adherenceRate))%</div>
                <div class="metric-label">Adherence Rate</div>
            </div>
            <div class="metric">
                <div class="metric-value">\(analytics.snoozeCount)</div>
                <div class="metric-label">Total Snoozes</div>
            </div>
        </div>
        """
    }
    
    private func generateSessionsHTML(_ sessions: [DoseSessionData]) -> String {
        var html = """
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Dose 1 Time</th>
                    <th>Dose 2 Time</th>
                    <th>Interval</th>
                    <th>Status</th>
                    <th>Events</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for session in sessions.sorted(by: { $0.startTime > $1.startTime }) {
            let dose1 = session.events.first { $0.type == .dose1 }
            let dose2 = session.events.first { $0.type == .dose2 }
            
            let date = formatDate(session.startTime)
            let dose1Time = dose1 != nil ? formatTime(dose1!.timestamp) : "—"
            let dose2Time = dose2 != nil ? formatTime(dose2!.timestamp) : "—"
            
            let interval: String
            let status: String
            let statusClass: String
            
            if let d1 = dose1, let d2 = dose2 {
                let intervalSeconds = d2.timestamp.timeIntervalSince(d1.timestamp)
                interval = formatDuration(intervalSeconds)
                let minutes = intervalSeconds / 60
                
                if minutes >= 150 && minutes <= 240 {
                    status = "Optimal"
                    statusClass = "status-good"
                } else if minutes >= 120 && minutes < 150 {
                    status = "Early"
                    statusClass = "status-warning"
                } else {
                    status = "Off-target"
                    statusClass = "status-poor"
                }
            } else {
                interval = "—"
                status = "Incomplete"
                statusClass = "status-poor"
            }
            
            let eventCount = session.events.count
            
            html += """
            <tr>
                <td>\(date)</td>
                <td>\(dose1Time)</td>
                <td>\(dose2Time)</td>
                <td>\(interval)</td>
                <td class="\(statusClass)">\(status)</td>
                <td>\(eventCount)</td>
            </tr>
            """
        }
        
        html += """
            </tbody>
        </table>
        """
        
        return html
    }
    
    private func generateHealthDataHTML(_ healthData: [HealthSleepData]) -> String {
        var html = """
        <h2>Apple Health Sleep Data</h2>
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Sleep Start</th>
                    <th>Sleep End</th>
                    <th>Total Sleep</th>
                    <th>Deep Sleep</th>
                    <th>REM Sleep</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for health in healthData.sorted(by: { $0.sleepDate > $1.sleepDate }) {
            let date = formatDate(health.sleepDate)
            let sleepStart = health.sleepStart != nil ? formatTime(health.sleepStart!) : "—"
            let sleepEnd = health.sleepEnd != nil ? formatTime(health.sleepEnd!) : "—"
            let totalSleep = health.totalSleepTime != nil ? formatDuration(health.totalSleepTime!) : "—"
            let deepSleep = health.deepSleepTime != nil ? formatDuration(health.deepSleepTime!) : "—"
            let remSleep = health.remSleepTime != nil ? formatDuration(health.remSleepTime!) : "—"
            
            html += """
            <tr>
                <td>\(date)</td>
                <td>\(sleepStart)</td>
                <td>\(sleepEnd)</td>
                <td>\(totalSleep)</td>
                <td>\(deepSleep)</td>
                <td>\(remSleep)</td>
            </tr>
            """
        }
        
        html += """
            </tbody>
        </table>
        """
        
        return html
    }
    
    private func generateWHOOPDataHTML(_ whoopData: [WHOOPSleepData]) -> String {
        var html = """
        <h2>WHOOP Sleep Data</h2>
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Sleep Score</th>
                    <th>Recovery Score</th>
                    <th>HRV</th>
                    <th>Strain</th>
                    <th>RHR</th>
                </tr>
            </thead>
            <tbody>
        """
        
        for whoop in whoopData.sorted(by: { $0.sleepDate > $1.sleepDate }) {
            let date = formatDate(whoop.sleepDate)
            let sleepScore = whoop.sleepScore?.description ?? "—"
            let recoveryScore = whoop.recoveryScore?.description ?? "—"
            let hrv = whoop.hrv != nil ? String(format: "%.1f", whoop.hrv!) : "—"
            let strain = whoop.strain != nil ? String(format: "%.1f", whoop.strain!) : "—"
            let rhr = whoop.restingHeartRate?.description ?? "—"
            
            html += """
            <tr>
                <td>\(date)</td>
                <td>\(sleepScore)</td>
                <td>\(recoveryScore)</td>
                <td>\(hrv)</td>
                <td>\(strain)</td>
                <td>\(rhr)</td>
            </tr>
            """
        }
        
        html += """
            </tbody>
        </table>
        """
        
        return html
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Export Data Models
public struct ComprehensiveExportData: Codable {
    let sessions: [DoseSessionData]
    let healthData: [HealthSleepData]
    let whoopData: [WHOOPSleepData]
    let analytics: AnalyticsData?
    let exportDate: Date
    let exportOptions: ExportOptions
}

extension DataExportService.ExportOptions: Codable {}

public struct AnalyticsData: Codable {
    let totalSessions: Int
    let completedSessions: Int
    let averageInterval: TimeInterval
    let adherenceRate: Double
    let totalEvents: Int
    let snoozeCount: Int
    let bathroomCount: Int
    let intervalDistribution: [String: Int]
}

// MARK: - Export Result
public enum ExportResult {
    case success(content: String, filename: String, format: DataExportService.ExportFormat)
    case failure(error: Error)
}

// MARK: - Export View
struct DataExportView: View {
    @StateObject private var exportService = DataExportService.shared
    @State private var selectedFormat: DataExportService.ExportFormat = .csv
    @State private var includeDoseEvents = true
    @State private var includeHealthData = true
    @State private var includeWHOOPData = true
    @State private var includeAnalytics = true
    @State private var useCustomDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showingShareSheet = false
    @State private var exportContent = ""
    @State private var exportFilename = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(DataExportService.ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Data to Include") {
                    Toggle("Dose Events", isOn: $includeDoseEvents)
                    Toggle("Apple Health Data", isOn: $includeHealthData)
                    Toggle("WHOOP Data", isOn: $includeWHOOPData)
                    Toggle("Analytics", isOn: $includeAnalytics)
                }
                
                Section("Date Range") {
                    Toggle("Use Custom Date Range", isOn: $useCustomDateRange)
                    
                    if useCustomDateRange {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
                
                Section {
                    Button("Export Data") {
                        Task {
                            await performExport()
                        }
                    }
                    .disabled(exportService.isExporting)
                }
                
                if exportService.isExporting {
                    Section {
                        ProgressView(value: exportService.exportProgress)
                        Text("Exporting data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [exportContent])
        }
    }
    
    private func performExport() async {
        let dateRange = useCustomDateRange ? 
            DataExportService.DateRange(start: startDate, end: endDate) : nil
        
        let options = DataExportService.ExportOptions(
            format: selectedFormat,
            includeDoseEvents: includeDoseEvents,
            includeHealthData: includeHealthData,
            includeWHOOPData: includeWHOOPData,
            dateRange: dateRange,
            includeAnalytics: includeAnalytics
        )
        
        let result = await exportService.exportData(options: options)
        
        switch result {
        case .success(let content, let filename, _):
            exportContent = content
            exportFilename = filename
            showingShareSheet = true
        case .failure(let error):
            print("Export failed: \(error)")
            // TODO: Show error alert
        }
    }
}

#Preview {
    DataExportView()
}
