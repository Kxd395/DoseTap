// Tests/DoseCoreTests/CSVExporterTests.swift
// Tests for CSV export functionality following SSOT CSV v1 format

import XCTest
@testable import DoseCore

final class CSVExporterTests: XCTestCase {
    
    // MARK: - Dose Export Tests
    
    func test_exportDoseRecords_includesHeader() {
        let csv = CSVExporter.exportDoseRecords([])
        XCTAssertTrue(csv.hasPrefix("Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake\n"))
    }
    
    func test_exportDoseRecords_emptyArrayProducesHeaderOnly() {
        let csv = CSVExporter.exportDoseRecords([])
        XCTAssertEqual(csv, "Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake\n")
    }
    
    func test_exportDoseRecords_singleRecord() {
        let date = makeDate(year: 2024, month: 1, day: 15)
        let dose1 = makeDateTime(year: 2024, month: 1, day: 15, hour: 22, minute: 30)
        let dose2 = makeDateTime(year: 2024, month: 1, day: 16, hour: 1, minute: 15)
        
        let record = DoseExportRecord(
            date: date,
            dose1Time: dose1,
            dose2Time: dose2,
            intervalMinutes: 165,
            onTime: true,
            naturalWake: false
        )
        
        let csv = CSVExporter.exportDoseRecords([record])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake")
        XCTAssertEqual(lines[1], "2024-01-15,22:30:00,01:15:00,165,true,false")
    }
    
    func test_exportDoseRecords_nilValuesAsEmptyStrings() {
        let date = makeDate(year: 2024, month: 1, day: 15)
        
        let record = DoseExportRecord(
            date: date,
            dose1Time: nil,
            dose2Time: nil,
            intervalMinutes: nil,
            onTime: false,
            naturalWake: true
        )
        
        let csv = CSVExporter.exportDoseRecords([record])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines[1], "2024-01-15,,,,false,true")
    }
    
    func test_exportDoseRecords_multipleRecords_deterministicOrder() {
        let date1 = makeDate(year: 2024, month: 1, day: 15)
        let date2 = makeDate(year: 2024, month: 1, day: 14)
        
        let record1 = DoseExportRecord(date: date1, dose1Time: nil, dose2Time: nil, intervalMinutes: nil, onTime: true, naturalWake: true)
        let record2 = DoseExportRecord(date: date2, dose1Time: nil, dose2Time: nil, intervalMinutes: nil, onTime: false, naturalWake: false)
        
        let csv = CSVExporter.exportDoseRecords([record1, record2])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("2024-01-15"))
        XCTAssertTrue(lines[2].hasPrefix("2024-01-14"))
    }
    
    // MARK: - Sleep Event Export Tests
    
    func test_exportSleepEvents_includesHeader() {
        let csv = CSVExporter.exportSleepEvents([])
        XCTAssertEqual(csv, "session_date,event_type,timestamp\n")
    }
    
    func test_exportSleepEvents_singleEvent() {
        let timestamp = makeDateTime(year: 2024, month: 1, day: 15, hour: 22, minute: 0)
        let event = SleepEventExportRecord(sessionDate: "2024-01-15", eventType: "lightsOut", timestamp: timestamp)
        
        let csv = CSVExporter.exportSleepEvents([event])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "session_date,event_type,timestamp")
        XCTAssertTrue(lines[1].contains("2024-01-15"))
        XCTAssertTrue(lines[1].contains("lightsOut"))
    }
    
    // MARK: - Generic Export Tests
    
    func test_exportGeneric_customHeaders() {
        let csv = CSVExporter.exportGeneric(headers: ["Name", "Value"], rows: [["foo", "bar"]])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines[0], "Name,Value")
        XCTAssertEqual(lines[1], "foo,bar")
    }
    
    func test_exportGeneric_escapesCommasInFields() {
        let csv = CSVExporter.exportGeneric(headers: ["Data"], rows: [["hello, world"]])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines[1], "\"hello, world\"")
    }
    
    func test_exportGeneric_escapesQuotesInFields() {
        let csv = CSVExporter.exportGeneric(headers: ["Data"], rows: [["say \"hello\""]])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines[1], "\"say \"\"hello\"\"\"")
    }
    
    func test_exportGeneric_escapesNewlinesInFields() {
        let csv = CSVExporter.exportGeneric(headers: ["Data"], rows: [["line1\nline2"]])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        // The field should be quoted since it contains a newline
        XCTAssertTrue(lines[1].hasPrefix("\""))
    }
    
    // MARK: - Validation Tests
    
    func test_validateDoseCSV_validCSV_noErrors() {
        let csv = """
        Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
        2024-01-15,22:30:00,01:15:00,165,true,false
        """
        
        let errors = CSVExporter.validateDoseCSV(csv)
        XCTAssertTrue(errors.isEmpty, "Errors: \(errors)")
    }
    
    func test_validateDoseCSV_wrongHeader_returnsError() {
        let csv = """
        Date,Dose1,Dose2,Interval,OnTime,NaturalWake
        2024-01-15,22:30:00,01:15:00,165,true,false
        """
        
        let errors = CSVExporter.validateDoseCSV(csv)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors[0].contains("Header mismatch"))
    }
    
    func test_validateDoseCSV_wrongFieldCount_returnsError() {
        let csv = """
        Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
        2024-01-15,22:30:00,01:15:00,165
        """
        
        let errors = CSVExporter.validateDoseCSV(csv)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors[0].contains("expected 6 fields"))
    }
    
    func test_validateDoseCSV_emptyCSV_returnsError() {
        let errors = CSVExporter.validateDoseCSV("")
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0], "CSV is empty")
    }
    
    // MARK: - SSOT Compliance Tests
    
    func test_exportMatchesSSOTFormat() {
        // SSOT format: Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
        // Example: 2024-01-15,22:30:00,01:15:00,165,true,false
        
        let date = makeDate(year: 2024, month: 1, day: 15)
        let dose1 = makeDateTime(year: 2024, month: 1, day: 15, hour: 22, minute: 30)
        let dose2 = makeDateTime(year: 2024, month: 1, day: 16, hour: 1, minute: 15)
        
        let record = DoseExportRecord(
            date: date,
            dose1Time: dose1,
            dose2Time: dose2,
            intervalMinutes: 165,
            onTime: true,
            naturalWake: false
        )
        
        let csv = CSVExporter.exportDoseRecords([record])
        
        // Validate against SSOT format
        let errors = CSVExporter.validateDoseCSV(csv)
        XCTAssertTrue(errors.isEmpty, "SSOT validation failed: \(errors)")
        
        // Check exact format match
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "2024-01-15,22:30:00,01:15:00,165,true,false")
    }
    
    // MARK: - Helpers
    
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
    
    private func makeDateTime(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
