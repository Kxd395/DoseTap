import Foundation
import DoseCore
import os.log

enum SettingsExportFormat {
    case studioBundle
    case excelWorkbook
}

/// Consumes one finalized reporting snapshot. Never reads or mutates the database.
enum ExcelWorkbookFileExporter {
    static func write(from sourceDirectory: URL, to destination: URL) throws {
        try Task.checkCancellation()
        let bundle = try Data(contentsOf: sourceDirectory.appendingPathComponent("insights_bundle.json"))
        let inventory = try String(contentsOf: sourceDirectory.appendingPathComponent("inventory.csv"), encoding: .utf8)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: bundle, inventoryCSV: inventory)
        let data = try ExcelWorkbookWriter.encode(sheets: sheets)
        try Task.checkCancellation()
        try data.write(to: destination, options: .atomic)
    }
}

private let workbookExportLog = Logger(subsystem: "com.dosetap.app", category: "SettingsExport")

extension SettingsView {
    @MainActor
    func exportData(format: SettingsExportFormat) {
        guard !isExporting else { return }
        isExporting = true
        requestedExportFormat = format
        exportStatus = "Preparing your records…"
        Task { @MainActor in
            await exportDataAsync(format: format)
        }
    }

    @MainActor
    private func exportDataAsync(format: SettingsExportFormat) async {
        let repo = SessionRepository.shared
        let tempDirectory = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.exportDateFormatter.string(from: Date())
        let exportDirectory = tempDirectory.appendingPathComponent("DoseTapStudioExport_\(timestamp)_\(UUID().uuidString)", isDirectory: true)
        let exporter = StudioBundleExporter()
        var unpublishedArchive: URL?
        var exportStep = "Preparing the export folder"
        defer {
            isExporting = false
            exportStatus = ""
            try? FileManager.default.removeItem(at: exportDirectory)
            if let unpublishedArchive { try? FileManager.default.removeItem(at: unpublishedArchive) }
        }

        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            exportStep = "Reading records and preparing the bundle"
            exportStatus = "Reading records and available sleep data…"
            try await exporter.writeStudioExportBundle(using: repo, to: exportDirectory)
            let archiveURL: URL
            switch format {
            case .studioBundle:
                exportStep = "Creating the ZIP archive"
                exportStatus = "Preparing the Studio bundle…"
                archiveURL = try exporter.archiveExportDirectory(exportDirectory)
                unpublishedArchive = archiveURL
            case .excelWorkbook:
                exportStep = "Creating the Excel workbook"
                exportStatus = "Styling your sortable Excel sheets…"
                archiveURL = tempDirectory.appendingPathComponent("DoseTapReview_\(timestamp)_\(UUID().uuidString).xlsx")
                unpublishedArchive = archiveURL
                try await Task.detached(priority: .userInitiated) {
                    try ExcelWorkbookFileExporter.write(from: exportDirectory, to: archiveURL)
                }.value
            }
            try Task.checkCancellation()

            exportArchive = StudioExportArchive(url: archiveURL)
            unpublishedArchive = nil
            workbookExportLog.info("Export created: \(archiveURL.lastPathComponent, privacy: .private)")
        } catch is CancellationError {
            return
        } catch {
            workbookExportLog.error("Failed to create export file: \(error.localizedDescription, privacy: .private)")
            exportErrorMessage = StudioExportFailureMessage.make(error, step: exportStep)
            showingExportError = true
        }
    }

}
