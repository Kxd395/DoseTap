// Export/CSVExporter.swift
import Foundation

enum CSVExporter {
    static func exportEventsCSV(to url: URL) throws {
        let csv = SessionRepository.shared.exportToCSVv2()
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportSessionsCSV(to url: URL) throws {
        let csv = SessionRepository.shared.exportToCSVv2()
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
