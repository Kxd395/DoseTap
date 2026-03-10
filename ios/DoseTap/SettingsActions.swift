import Foundation
import os.log
import UserNotifications
import DoseCore
#if canImport(UIKit)
import UIKit
#endif

private let settingsActionsLog = Logger(subsystem: "com.dosetap.app", category: "SettingsView")

extension SettingsView {
    @MainActor
    func validateNotificationAuthorization() async {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = await AlarmService.shared.requestPermission()
            if !granted {
                settings.notificationsEnabled = false
                notificationPermissionMessage = "DoseTap cannot play notification alarms until you grant notification permission."
                showingNotificationPermissionAlert = true
            }
        case .denied:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "Notifications are denied for DoseTap in iOS Settings. Enable them to receive wake alarms when the app is backgrounded or the phone is locked."
            showingNotificationPermissionAlert = true
        @unknown default:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "DoseTap could not verify notification permission. Please enable notifications in iOS Settings."
            showingNotificationPermissionAlert = true
        }
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func openSystemNotificationSettings() {
        #if canImport(UIKit)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
        #endif
    }

    func exportData() {
        let repo = SessionRepository.shared
        let tempDirectory = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.exportDateFormatter.string(from: Date())
        let exportDirectory = tempDirectory.appendingPathComponent("DoseTapStudioExport_\(timestamp)", isDirectory: true)

        do {
            try? FileManager.default.removeItem(at: exportDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try writeStudioExportBundle(using: repo, to: exportDirectory)
            let archiveURL = try archiveExportDirectory(exportDirectory)

            exportItems = [archiveURL]
            showingExportSheet = true
            settingsActionsLog.info("Studio export created: \(archiveURL.lastPathComponent, privacy: .private)")
        } catch {
            settingsActionsLog.error("Failed to create export file: \(error.localizedDescription, privacy: .public)")
            exportErrorMessage = error.localizedDescription
            showingExportError = true
        }
    }

    func clearAllData() {
        #if DEBUG
        settingsActionsLog.debug("Clearing all data")
        #endif

        SessionRepository.shared.clearAllData()

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        settings.resetToDefaults()
        sleepPlanStore.resetToDefaults()
        SessionRepository.shared.reload()

        #if DEBUG
        settingsActionsLog.debug("All data cleared successfully")
        #endif
    }

    private func buildInsightsBundle(using repo: SessionRepository) -> InsightsBundleExport {
        let sessionDates = repo.getAllSessions().sorted(by: >)
        let sessions = sessionDates.map { sessionDate in
            let preSleep = repo.fetchPreSleepLog(forSessionDate: sessionDate).map(exportPreSleepSummary(from:))
            let morning = repo.fetchMorningCheckIn(for: sessionDate).map(exportMorningSummary(from:))
            let medications = repo.listMedicationEntries(for: sessionDate).map(exportMedicationSummary(from:))
            return InsightsBundleSession(
                sessionDate: sessionDate,
                preSleep: preSleep,
                morning: morning,
                medications: medications
            )
        }

        return InsightsBundleExport(
            schemaVersion: 1,
            exportedAtUTC: Date(),
            sessions: sessions
        )
    }

    private func exportPreSleepSummary(from log: StoredPreSleepLog) -> InsightsPreSleepSummary {
        let answers = log.answers
        return InsightsPreSleepSummary(
            sessionId: log.sessionId,
            completionState: log.completionState,
            loggedAtUTC: log.createdAtUtc,
            stressLevel: answers?.stressLevel,
            stressDrivers: answers?.resolvedStressDrivers.map(\.rawValue) ?? [],
            laterReason: answers?.laterReason?.rawValue,
            bodyPain: answers?.bodyPain?.rawValue,
            caffeineSources: answers?.resolvedCaffeineSources.map(\.rawValue) ?? [],
            alcohol: answers?.alcohol?.rawValue,
            exercise: answers?.exercise?.rawValue,
            napToday: answers?.napToday?.rawValue,
            lateMeal: answers?.lateMeal?.rawValue,
            screensInBed: answers?.screensInBed?.rawValue,
            roomTemp: answers?.roomTemp?.rawValue,
            noiseLevel: answers?.noiseLevel?.rawValue,
            sleepAids: answers?.resolvedSleepAidSelections.map(\.rawValue) ?? [],
            notes: answers?.notes
        )
    }

    private func exportMorningSummary(from checkIn: StoredMorningCheckIn) -> InsightsMorningSummary {
        InsightsMorningSummary(
            submittedAtUTC: checkIn.timestamp,
            sleepQuality: checkIn.sleepQuality,
            feelRested: checkIn.feelRested,
            grogginess: checkIn.grogginess,
            sleepInertiaDuration: checkIn.sleepInertiaDuration,
            dreamRecall: checkIn.dreamRecall,
            mentalClarity: checkIn.mentalClarity,
            mood: checkIn.mood,
            anxietyLevel: checkIn.anxietyLevel,
            stressLevel: checkIn.stressLevel,
            stressDrivers: checkIn.resolvedStressDrivers.map(\.rawValue),
            readinessForDay: checkIn.readinessForDay,
            hadSleepParalysis: checkIn.hadSleepParalysis,
            hadHallucinations: checkIn.hadHallucinations,
            hadAutomaticBehavior: checkIn.hadAutomaticBehavior,
            fellOutOfBed: checkIn.fellOutOfBed,
            hadConfusionOnWaking: checkIn.hadConfusionOnWaking,
            notes: checkIn.notes
        )
    }

    private func exportMedicationSummary(from entry: DoseCore.MedicationEntry) -> InsightsMedicationSummary {
        let formulation = MedicationConfig.type(for: entry.medicationId).map { type in
            switch type.formulation {
            case .immediateRelease: return "ir"
            case .extendedRelease: return "xr"
            case .liquid: return "liquid"
            }
        } ?? "ir"

        return InsightsMedicationSummary(
            id: entry.id,
            medicationId: entry.medicationId,
            doseMg: entry.doseMg,
            doseUnit: "mg",
            formulation: formulation,
            takenAtUTC: entry.takenAtUTC,
            notes: entry.notes
        )
    }

    private func writeStudioExportBundle(using repo: SessionRepository, to directory: URL) throws {
        let sessionDates = repo.getAllSessions().sorted()
        try buildStudioEventsCSV(using: repo, sessionDates: sessionDates)
            .write(to: directory.appendingPathComponent("events.csv"), atomically: true, encoding: .utf8)
        try buildStudioSessionsCSV(using: repo, sessionDates: sessionDates)
            .write(to: directory.appendingPathComponent("sessions.csv"), atomically: true, encoding: .utf8)
        try buildStudioInventoryCSV()
            .write(to: directory.appendingPathComponent("inventory.csv"), atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(buildInsightsBundle(using: repo))
            .write(to: directory.appendingPathComponent("insights_bundle.json"), options: .atomic)
    }

    private func buildStudioEventsCSV(using repo: SessionRepository, sessionDates: [String]) -> String {
        var rows = ["event_type,occurred_at_utc,details,device_time"]
        for sessionDate in sessionDates {
            let doseEvents = repo.fetchDoseEvents(forSessionDate: sessionDate)
                .map { event in
                    studioCSVRow(
                        eventType: event.eventType,
                        timestamp: event.timestamp,
                        details: event.metadata,
                        deviceTime: sessionDate
                    )
                }
            let sleepEvents = repo.fetchSleepEvents(for: sessionDate)
                .map { event in
                    studioCSVRow(
                        eventType: event.eventType,
                        timestamp: event.timestamp,
                        details: event.notes,
                        deviceTime: sessionDate
                    )
                }
            rows.append(contentsOf: (doseEvents + sleepEvents).sorted())
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func buildStudioSessionsCSV(using repo: SessionRepository, sessionDates: [String]) -> String {
        var rows = ["started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes"]
        for sessionDate in sessionDates {
            guard let doseLog = repo.fetchDoseLog(forSession: sessionDate) else { continue }
            let startedUTC = doseLog.dose1Time
            let endedUTC = doseLog.dose2Time
            let adherenceFlag = doseLog.dose2Skipped ? "missed" : (doseLog.intervalMinutes ?? 0) > 240 ? "late" : "ok"
            let row = [
                AppFormatters.iso8601Fractional.string(from: startedUTC),
                endedUTC.map(AppFormatters.iso8601Fractional.string(from:)) ?? "",
                String(settings.targetIntervalMinutes),
                doseLog.intervalMinutes.map(String.init) ?? "",
                adherenceFlag,
                "",
                "",
                "",
                ""
            ].map(csvField).joined(separator: ",")
            rows.append(row)
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func buildStudioInventoryCSV() -> String {
        "as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes\n"
    }

    private func studioCSVRow(eventType: String, timestamp: Date, details: String?, deviceTime: String?) -> String {
        [
            eventType,
            AppFormatters.iso8601Fractional.string(from: timestamp),
            details ?? "",
            deviceTime ?? ""
        ]
        .map(csvField)
        .joined(separator: ",")
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func archiveExportDirectory(_ directory: URL) throws -> URL {
        let archiveURL = directory.deletingLastPathComponent().appendingPathComponent("\(directory.lastPathComponent).zip")
        try? FileManager.default.removeItem(at: archiveURL)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: archiveURL)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        if let copyError {
            throw copyError
        }
        return archiveURL
    }
}

private struct InsightsBundleExport: Codable {
    let schemaVersion: Int
    let exportedAtUTC: Date
    let sessions: [InsightsBundleSession]
}

private struct InsightsBundleSession: Codable {
    let sessionDate: String
    let preSleep: InsightsPreSleepSummary?
    let morning: InsightsMorningSummary?
    let medications: [InsightsMedicationSummary]
}

private struct InsightsPreSleepSummary: Codable {
    let sessionId: String?
    let completionState: String
    let loggedAtUTC: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let laterReason: String?
    let bodyPain: String?
    let caffeineSources: [String]
    let alcohol: String?
    let exercise: String?
    let napToday: String?
    let lateMeal: String?
    let screensInBed: String?
    let roomTemp: String?
    let noiseLevel: String?
    let sleepAids: [String]
    let notes: String?
}

private struct InsightsMorningSummary: Codable {
    let submittedAtUTC: Date
    let sleepQuality: Int
    let feelRested: String
    let grogginess: String
    let sleepInertiaDuration: String
    let dreamRecall: String
    let mentalClarity: Int
    let mood: String
    let anxietyLevel: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let readinessForDay: Int
    let hadSleepParalysis: Bool
    let hadHallucinations: Bool
    let hadAutomaticBehavior: Bool
    let fellOutOfBed: Bool
    let hadConfusionOnWaking: Bool
    let notes: String?
}

private struct InsightsMedicationSummary: Codable {
    let id: String
    let medicationId: String
    let doseMg: Int
    let doseUnit: String
    let formulation: String
    let takenAtUTC: Date
    let notes: String?
}
