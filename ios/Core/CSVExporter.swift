// ios/Core/CSVExporter.swift
// DoseCore - Platform-free CSV export utilities

import Foundation

// MARK: - CSV Export Models

/// A single dose session record for CSV export
/// Follows SSOT CSV v1 format: Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
public struct DoseExportRecord: Equatable, Sendable {
    public let date: Date
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let intervalMinutes: Int?
    public let onTime: Bool
    public let naturalWake: Bool
    
    public init(
        date: Date,
        dose1Time: Date?,
        dose2Time: Date?,
        intervalMinutes: Int?,
        onTime: Bool,
        naturalWake: Bool
    ) {
        self.date = date
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.intervalMinutes = intervalMinutes
        self.onTime = onTime
        self.naturalWake = naturalWake
    }
}

/// Sleep event record for CSV export
public struct SleepEventExportRecord: Equatable, Sendable {
    public let sessionDate: String  // ISO8601 date only
    public let eventType: String
    public let timestamp: Date
    
    public init(sessionDate: String, eventType: String, timestamp: Date) {
        self.sessionDate = sessionDate
        self.eventType = eventType
        self.timestamp = timestamp
    }
}

// MARK: - CSV Exporter

/// Platform-free CSV exporter following SSOT CSV v1 format rules:
/// - Header always included
/// - Deterministic column order
/// - ISO8601 timestamps
/// - Empty string for nil values
public struct CSVExporter: Sendable {
    
    /// Time formatter for HH:mm:ss format
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    /// Date formatter for YYYY-MM-DD format
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    /// ISO8601 formatter for full timestamps
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    // MARK: - Dose Export
    
    /// Export dose records to CSV following SSOT format
    /// Format: Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
    public static func exportDoseRecords(_ records: [DoseExportRecord]) -> String {
        var csv = "Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake\n"
        
        for record in records {
            let dateStr = dateFormatter.string(from: record.date)
            let dose1Str = record.dose1Time.map { timeFormatter.string(from: $0) } ?? ""
            let dose2Str = record.dose2Time.map { timeFormatter.string(from: $0) } ?? ""
            let intervalStr = record.intervalMinutes.map { String($0) } ?? ""
            let onTimeStr = record.onTime ? "true" : "false"
            let naturalWakeStr = record.naturalWake ? "true" : "false"
            
            csv += "\(dateStr),\(dose1Str),\(dose2Str),\(intervalStr),\(onTimeStr),\(naturalWakeStr)\n"
        }
        
        return csv
    }
    
    // MARK: - Sleep Event Export
    
    /// Export sleep events to CSV
    /// Format: session_date,event_type,timestamp
    public static func exportSleepEvents(_ events: [SleepEventExportRecord]) -> String {
        var csv = "session_date,event_type,timestamp\n"
        
        for event in events {
            let timestampStr = iso8601Formatter.string(from: event.timestamp)
            csv += "\(event.sessionDate),\(event.eventType),\(timestampStr)\n"
        }
        
        return csv
    }
    
    // MARK: - Generic CSV Export
    
    /// Export generic rows to CSV with custom headers
    /// - Parameters:
    ///   - headers: Column headers
    ///   - rows: Array of row data (each row is array of strings)
    /// - Returns: CSV string
    public static func exportGeneric(headers: [String], rows: [[String]]) -> String {
        var csv = headers.joined(separator: ",") + "\n"
        
        for row in rows {
            // Escape fields containing commas, quotes, or newlines
            let escaped = row.map { escapeCSVField($0) }
            csv += escaped.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    // MARK: - Validation
    
    /// Validate CSV format matches SSOT v1 requirements
    /// - Returns: Array of validation errors, empty if valid
    public static func validateDoseCSV(_ csv: String) -> [String] {
        var errors: [String] = []
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            errors.append("CSV is empty")
            return errors
        }
        
        // Check header
        let expectedHeader = "Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake"
        if lines[0] != expectedHeader {
            errors.append("Header mismatch: expected '\(expectedHeader)', got '\(lines[0])'")
        }
        
        // Check each data row
        for (index, line) in lines.dropFirst().enumerated() {
            let fields = line.components(separatedBy: ",")
            if fields.count != 6 {
                errors.append("Row \(index + 1): expected 6 fields, got \(fields.count)")
            }
        }
        
        return errors
    }
    
    // MARK: - Helpers
    
    /// Escape a CSV field if it contains special characters
    private static func escapeCSVField(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n")
        if needsQuoting {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
