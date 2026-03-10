// AutoExportService.swift — P3-7 Scheduled auto-export to Files app
// Uses BGTaskScheduler for weekly/monthly background CSV export.
import Foundation
import BackgroundTasks
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let autoExportLog = Logger(subsystem: "com.dosetap.app", category: "AutoExport")

/// Manages scheduled background exports of dose/session data to the Files app.
final class AutoExportService {
    static let shared = AutoExportService()

    /// BGTask identifier — must also be registered in Info.plist BGTaskSchedulerPermittedIdentifiers.
    static var taskIdentifier: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.dosetap.ios"
        return "\(bundleIdentifier).export.scheduled"
    }

    /// Export frequency options
    enum Frequency: String, CaseIterable, Identifiable {
        case weekly  = "Weekly"
        case monthly = "Monthly"
        var id: String { rawValue }
        var calendarComponent: Calendar.Component {
            switch self {
            case .weekly:  return .weekOfYear
            case .monthly: return .month
            }
        }
    }

    // MARK: - UserDefaults keys (mirrored in UserSettingsManager)
    private let enabledKey  = "auto_export_enabled"
    private let frequencyKey = "auto_export_frequency"
    private let lastExportKey = "auto_export_last_date"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { scheduleNextExport() } else { cancelScheduledExport() }
        }
    }

    var frequency: Frequency {
        get {
            let raw = UserDefaults.standard.string(forKey: frequencyKey) ?? Frequency.weekly.rawValue
            return Frequency(rawValue: raw) ?? .weekly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey)
            if isEnabled { scheduleNextExport() }
        }
    }

    var lastExportDate: Date? {
        get { UserDefaults.standard.object(forKey: lastExportKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastExportKey) }
    }

    private init() {}

    // MARK: - Registration (call once from app init)

    /// Register the BGProcessingTask with the system. Call this in `DoseTapApp.init()`.
    func registerBackgroundTask() {
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self?.handleBackgroundExport(task: processingTask)
        }
        if didRegister {
            autoExportLog.info("Background export task registered for \(Self.taskIdentifier, privacy: .public)")
        } else {
            autoExportLog.error("Failed to register background export task for \(Self.taskIdentifier, privacy: .public)")
        }
    }

    // MARK: - Scheduling

    func scheduleNextExport() {
        guard isEnabled else {
            cancelScheduledExport()
            return
        }

        // Keep a single pending request for this identifier so reschedules don't fail.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        // Schedule for next interval from now (or from last export)
        let baseDate = lastExportDate ?? Date()
        let nextDate = Calendar.current.date(byAdding: frequency.calendarComponent, value: 1, to: baseDate) ?? Date().addingTimeInterval(7 * 86400)
        request.earliestBeginDate = nextDate

        do {
            try BGTaskScheduler.shared.submit(request)
            autoExportLog.info("Scheduled next export for ≈\(nextDate.formatted(), privacy: .public)")
        } catch {
            autoExportLog.error("Failed to schedule export: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelScheduledExport() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        autoExportLog.info("Cancelled scheduled export")
    }

    // MARK: - Background handler

    private func handleBackgroundExport(task: BGProcessingTask) {
        guard isEnabled else {
            autoExportLog.info("Skipping background export because scheduled export is disabled")
            task.setTaskCompleted(success: false)
            return
        }

        // Schedule the next occurrence before doing work
        scheduleNextExport()

        task.expirationHandler = {
            autoExportLog.warning("Background export expired before completion")
        }

        Task { @MainActor in
            let success = performExport()
            task.setTaskCompleted(success: success)
        }
    }

    // MARK: - Export logic

    /// Run export synchronously. Returns true on success.
    @discardableResult
    @MainActor
    func performExport() -> Bool {
        guard isEnabled else {
            autoExportLog.info("Skipping export because scheduled export is disabled")
            return false
        }

        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            autoExportLog.error("No documents directory available")
            return false
        }

        let exportDir = docsURL.appendingPathComponent("DoseTap Exports", isDirectory: true)
        do {
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            autoExportLog.error("Could not create export dir: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let dateStr = DateFormatter.exportDateFormatter.string(from: Date())
        let csvContent = SessionRepository.shared.exportToCSV()
        let fileURL = exportDir.appendingPathComponent("DoseTap_AutoExport_\(dateStr).csv")

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            lastExportDate = Date()
            autoExportLog.info("Auto-export saved: \(fileURL.lastPathComponent, privacy: .public)")
            return true
        } catch {
            autoExportLog.error("Auto-export failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
