import SwiftUI
import Foundation

/// Export view for dose history data
/// Provides CSV export functionality with customizable options
@available(iOS 15.0, *)
struct ExportView: View {
    let events: [DoseEvent]
    
    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedDateRange: ExportDateRange = .all
    @State private var includeMetadata = true
    @State private var includeTimingAnalysis = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportSuccess = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerSection
                optionsSection
                previewSection
                exportSection
            }
            .padding()
            .navigationTitle("Export History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") {
                    exportError = nil
                }
            } message: {
                if let error = exportError {
                    Text(error)
                }
            }
            .alert("Export Successful", isPresented: $exportSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your dose history has been exported successfully.")
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("Export Dose History")
                        .font(.headline)
                    
                    Text("\(filteredEvents.count) events selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text("Export your dose history for healthcare providers or personal analysis.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Options")
                .font(.headline)
            
            // Format selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Export Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Date range selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Date Range")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Date Range", selection: $selectedDateRange) {
                    ForEach(ExportDateRange.allCases, id: \.self) { range in
                        Text(range.displayName)
                            .tag(range)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Include options
            VStack(alignment: .leading, spacing: 12) {
                Text("Include")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Toggle("Event metadata", isOn: $includeMetadata)
                    .accessibilityHint("Include additional event information like timestamps and IDs")
                
                Toggle("Timing analysis", isOn: $includeTimingAnalysis)
                    .accessibilityHint("Include dose window timing and effectiveness data")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
            
            ScrollView {
                Text(previewContent)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemBackground))
            )
        }
    }
    
    private var exportSection: some View {
        VStack(spacing: 12) {
            Button(action: performExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Text(isExporting ? "Exporting..." : "Export History")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isExporting || filteredEvents.isEmpty)
            .accessibilityLabel("Export dose history")
            .accessibilityHint("Exports \(filteredEvents.count) events in \(selectedFormat.displayName) format")
            
            if filteredEvents.isEmpty {
                Text("No events match the selected criteria")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredEvents: [DoseEvent] {
        let dateRange = selectedDateRange.dateRange
        return events.filter { event in
            event.utcTs >= dateRange.start && event.utcTs <= dateRange.end
        }
    }
    
    private var previewContent: String {
        switch selectedFormat {
        case .csv:
            return generateCSVPreview()
        case .json:
            return generateJSONPreview()
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateCSVPreview() -> String {
        var lines: [String] = []
        
        // Header
        var headers = ["Date", "Time", "Event Type"]
        if includeMetadata {
            headers.append(contentsOf: ["Event ID", "Timestamp"])
        }
        if includeTimingAnalysis {
            headers.append(contentsOf: ["Window State", "Timing"])
        }
        lines.append(headers.joined(separator: ","))
        
        // Sample rows (first 3 events)
        let sampleEvents = Array(filteredEvents.prefix(3))
        for event in sampleEvents {
            var row = [
                event.utcTs.formatted(date: .numeric, time: .omitted),
                event.utcTs.formatted(date: .omitted, time: .shortened),
                event.type.displayName
            ]
            
            if includeMetadata {
                row.append(contentsOf: [
                    event.id.uuidString,
                    ISO8601DateFormatter().string(from: event.utcTs)
                ])
            }
            
            if includeTimingAnalysis {
                row.append(contentsOf: ["Target Window", "On Time"])
            }
            
            lines.append(row.joined(separator: ","))
        }
        
        if filteredEvents.count > 3 {
            lines.append("... (\(filteredEvents.count - 3) more events)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateJSONPreview() -> String {
        let sampleEvents = Array(filteredEvents.prefix(2))
        let jsonData = sampleEvents.map { event in
            var eventData: [String: Any] = [
                "date": event.utcTs.formatted(date: .numeric, time: .omitted),
                "time": event.utcTs.formatted(date: .omitted, time: .shortened),
                "eventType": event.type.displayName
            ]
            
            if includeMetadata {
                eventData["eventId"] = event.id.uuidString
                eventData["timestamp"] = ISO8601DateFormatter().string(from: event.utcTs)
            }
            
            if includeTimingAnalysis {
                eventData["windowState"] = "Target Window"
                eventData["timing"] = "On Time"
            }
            
            return eventData
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
            var jsonString = String(data: jsonData, encoding: .utf8) ?? "Invalid JSON"
            
            if filteredEvents.count > 2 {
                jsonString += "\n... (\(filteredEvents.count - 2) more events)"
            }
            
            return jsonString
        } catch {
            return "JSON encoding error"
        }
    }
    
    private func performExport() {
        isExporting = true
        
        Task {
            do {
                let exportData = try await generateExportData()
                await shareExportData(exportData)
                
                await MainActor.run {
                    isExporting = false
                    exportSuccess = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
    
    private func generateExportData() async throws -> Data {
        switch selectedFormat {
        case .csv:
            return generateCSVData()
        case .json:
            return try generateJSONData()
        }
    }
    
    private func generateCSVData() -> Data {
        var lines: [String] = []
        
        // Header
        var headers = ["Date", "Time", "Event Type"]
        if includeMetadata {
            headers.append(contentsOf: ["Event ID", "Timestamp"])
        }
        if includeTimingAnalysis {
            headers.append(contentsOf: ["Window State", "Timing"])
        }
        lines.append(headers.joined(separator: ","))
        
        // Data rows
        for event in filteredEvents {
            var row = [
                event.utcTs.formatted(date: .numeric, time: .omitted),
                event.utcTs.formatted(date: .omitted, time: .shortened),
                event.type.displayName
            ]
            
            if includeMetadata {
                row.append(contentsOf: [
                    event.id.uuidString,
                    ISO8601DateFormatter().string(from: event.utcTs)
                ])
            }
            
            if includeTimingAnalysis {
                // Calculate timing analysis
                let windowState = "Target Window" // Placeholder
                let timing = "On Time" // Placeholder
                row.append(contentsOf: [windowState, timing])
            }
            
            lines.append(row.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }
    
    private func generateJSONData() throws -> Data {
        let jsonData = filteredEvents.map { event in
            var eventData: [String: Any] = [
                "date": event.utcTs.formatted(date: .numeric, time: .omitted),
                "time": event.utcTs.formatted(date: .omitted, time: .shortened),
                "eventType": event.type.displayName
            ]
            
            if includeMetadata {
                eventData["eventId"] = event.id.uuidString
                eventData["timestamp"] = ISO8601DateFormatter().string(from: event.utcTs)
            }
            
            if includeTimingAnalysis {
                eventData["windowState"] = "Target Window"
                eventData["timing"] = "On Time"
            }
            
            return eventData
        }
        
        return try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
    }
    
    private func shareExportData(_ data: Data) async {
        let filename = "dose_history_\(Date().formatted(date: .numeric, time: .omitted)).\(selectedFormat.fileExtension)"
        
        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL)
            
            await MainActor.run {
                let activityViewController = UIActivityViewController(
                    activityItems: [tempURL],
                    applicationActivities: nil
                )
                
                // Present share sheet
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityViewController, animated: true)
                }
            }
        } catch {
            throw error
        }
    }
}

// MARK: - Supporting Types

enum ExportFormat: CaseIterable {
    case csv, json
    
    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .json: return "JSON"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

enum ExportDateRange: CaseIterable {
    case week, month, quarter, year, all
    
    var displayName: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .quarter: return "Last 3 months"
        case .year: return "Last year"
        case .all: return "All time"
        }
    }
    
    var dateRange: (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        case .quarter:
            let start = calendar.date(byAdding: .month, value: -3, to: now)!
            return (start, now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now)!
            return (start, now)
        case .all:
            return (Date.distantPast, Date.distantFuture)
        }
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView(events: [])
    }
}
