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
        Task { @MainActor in
            await exportDataAsync()
        }
    }

    @MainActor
    private func exportDataAsync() async {
        let repo = SessionRepository.shared
        let tempDirectory = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.exportDateFormatter.string(from: Date())
        let exportDirectory = tempDirectory.appendingPathComponent("DoseTapStudioExport_\(timestamp)", isDirectory: true)

        do {
            try? FileManager.default.removeItem(at: exportDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try await writeStudioExportBundle(using: repo, to: exportDirectory)
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

    @MainActor
    private func buildInsightsBundle(
        using repo: SessionRepository,
        sessionDates: [String],
        enrichmentBySessionDate: [String: StudioExportSessionContext],
        consent: InsightsConsentState
    ) -> InsightsBundleExport {
        let sortedSessionDates = sessionDates.sorted(by: >)
        let sessions = sortedSessionDates.map { sessionDate in
            let doseLog = repo.fetchDoseLog(forSession: sessionDate)
            let doseEvents = repo.fetchDoseEvents(forSessionDate: sessionDate)
            let sleepEvents = repo.fetchSleepEvents(for: sessionDate)
            let preSleepLog = repo.fetchPreSleepLog(forSessionDate: sessionDate)
            let morningCheckIn = repo.fetchMorningCheckIn(for: sessionDate)
            let sessionId = repo.fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
            let rawEvents = exportRawEvents(doseEvents: doseEvents, sleepEvents: sleepEvents, sessionDate: sessionDate)
            let normalizedEvents = exportNormalizedEvents(from: rawEvents)
            let preSleep = preSleepLog.map(exportPreSleepSummary(from:))
            let morning = morningCheckIn.map(exportMorningSummary(from:))
            let medications = repo.listMedicationEntries(for: sessionDate).map(exportMedicationSummary(from:))
            let healthKit = enrichmentBySessionDate[sessionDate]?.healthKit
            let whoop = enrichmentBySessionDate[sessionDate]?.whoop
            let alarmContext = exportAlarmContext(forSessionId: sessionId)
            let exportExclusionReasons = buildSessionExportExclusionReasons(
                doseLog: doseLog,
                doseEvents: doseEvents,
                sleepEvents: sleepEvents,
                morningCheckIn: morningCheckIn
            )
            return InsightsBundleSession(
                sessionDate: sessionDate,
                dose1TimeUTC: doseLog?.dose1Time,
                dose2TimeUTC: doseLog?.dose2Time,
                rawEvents: rawEvents,
                normalizedEvents: normalizedEvents,
                sourceAvailability: InsightsSourceAvailability(
                    doseEvents: !doseEvents.isEmpty,
                    sleepEvents: !sleepEvents.isEmpty,
                    preSleep: preSleep != nil,
                    morningCheckIn: morning != nil,
                    medications: !medications.isEmpty,
                    healthKit: healthKit != nil,
                    whoop: whoop != nil,
                    alarmDiagnostics: alarmContext != nil
                ),
                metricProvenance: buildMetricProvenance(
                    doseLog: doseLog,
                    doseEvents: doseEvents,
                    sleepEvents: sleepEvents,
                    preSleepLog: preSleepLog,
                    morningCheckIn: morningCheckIn,
                    healthKit: healthKit,
                    whoop: whoop
                ),
                dataQualityFlags: buildSessionDataQualityFlags(
                    doseLog: doseLog,
                    doseEvents: doseEvents,
                    sleepEvents: sleepEvents
                ),
                exportExclusionReasons: exportExclusionReasons,
                preSleep: preSleep,
                morning: morning,
                medications: medications,
                context: exportSessionContext(
                    sessionDate: sessionDate,
                    sessionId: sessionId,
                    doseLog: doseLog,
                    doseEvents: doseEvents,
                    preSleepLog: preSleepLog,
                    morningCheckIn: morningCheckIn,
                    sleepEvents: sleepEvents,
                    precomputedAlarmContext: alarmContext
                ),
                healthKit: healthKit,
                whoop: whoop
            )
        }

        return InsightsBundleExport(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: bundleVersionString(),
            exportedAtUTC: Date(),
            timeZoneIdentifier: TimeZone.current.identifier,
            localOffsetMinutes: TimeZone.current.secondsFromGMT(for: Date()) / 60,
            consent: consent,
            exportWarnings: buildBundleExportWarnings(sessions: sessions),
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
            caffeineLastIntakeAtUTC: answers?.caffeineLastIntakeAt,
            caffeineLastAmountMg: answers?.caffeineLastAmountMg,
            caffeineDailyTotalMg: answers?.caffeineDailyTotalMg,
            alcohol: answers?.alcohol?.rawValue,
            alcoholLastDrinkAtUTC: answers?.alcoholLastDrinkAt,
            alcoholLastAmountDrinks: answers?.alcoholLastAmountDrinks,
            alcoholDailyTotalDrinks: answers?.alcoholDailyTotalDrinks,
            exercise: answers?.exercise?.rawValue,
            exerciseLastAtUTC: answers?.exerciseLastAt,
            exerciseDurationMinutes: answers?.exerciseDurationMinutes,
            napToday: answers?.napToday?.rawValue,
            napCount: answers?.napCount,
            napTotalMinutes: answers?.napTotalMinutes,
            napLastEndAtUTC: answers?.napLastEndAt,
            lateMeal: answers?.lateMeal?.rawValue,
            lateMealEndedAtUTC: answers?.lateMealEndedAt,
            screensInBed: answers?.screensInBed?.rawValue,
            screensLastUsedAtUTC: answers?.screensLastUsedAt,
            roomTemp: answers?.roomTemp?.rawValue,
            noiseLevel: answers?.noiseLevel?.rawValue,
            sleepAids: answers?.resolvedSleepAidSelections.map(\.rawValue) ?? [],
            notes: answers?.notes
        )
    }

    private func exportMorningSummary(from checkIn: StoredMorningCheckIn) -> InsightsMorningSummary {
        let timingContext = checkIn.resolvedTimingContext
        let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
        let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
        let sleepTherapy = jsonDictionary(from: checkIn.sleepTherapyJson)
        return InsightsMorningSummary(
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
            sleepTherapyDevice: stringValue(from: sleepTherapy["device"]),
            sleepTherapyCompliance: intValue(from: sleepTherapy["compliance"]),
            drivingConfidence: timingContext?.drivingConfidence,
            daytimeSleepiness: timingContext?.daytimeSleepiness,
            cataplexyBurden: timingContext?.cataplexyBurden,
            painBurden: symptomBurdenValue(from: physical["painBurden"]) ?? derivedPainBurden(from: physical),
            anxietyBurden: normalizedOptionalString(checkIn.anxietyLevel),
            congestionBurden: symptomBurdenValue(from: respiratory["congestionBurden"]) ?? derivedCongestionBurden(from: respiratory),
            refluxBurden: symptomBurdenValue(from: physical["refluxBurden"]),
            restlessLegsBurden: symptomBurdenValue(from: physical["restlessLegsBurden"]),
            bathroomUrgencyBurden: symptomBurdenValue(from: physical["bathroomUrgencyBurden"]),
            sleepDisorders: timingContext?.sleepDisorders ?? [],
            sleepDisorderNotes: timingContext?.sleepDisorderNotes,
            coMedicationNotes: timingContext?.coMedicationNotes,
            pharmacogenomicFastMetabolizer: timingContext?.pharmacogenomicFastMetabolizer ?? false,
            pharmacogenomicClinicianReviewed: timingContext?.pharmacogenomicClinicianReviewed ?? false,
            pharmacogenomicNotes: timingContext?.pharmacogenomicNotes,
            firstNightOffAfterWorkBlock: timingContext?.firstNightOffAfterWorkBlock ?? false,
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

    @MainActor
    private func writeStudioExportBundle(using repo: SessionRepository, to directory: URL) async throws {
        let sessionDates = repo.getAllSessions().sorted()
        let consentState = await exportConsentState()
        let enrichmentBySessionDate = await collectStudioExportEnrichment(sessionDates: sessionDates)

        try buildStudioEventsCSV(using: repo, sessionDates: sessionDates)
            .write(to: directory.appendingPathComponent("events.csv"), atomically: true, encoding: .utf8)
        try buildStudioSessionsCSV(
            using: repo,
            sessionDates: sessionDates,
            enrichmentBySessionDate: enrichmentBySessionDate
        )
            .write(to: directory.appendingPathComponent("sessions.csv"), atomically: true, encoding: .utf8)
        try buildStudioInventoryCSV()
            .write(to: directory.appendingPathComponent("inventory.csv"), atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            buildInsightsBundle(
                using: repo,
                sessionDates: sessionDates,
                enrichmentBySessionDate: enrichmentBySessionDate,
                consent: consentState
            )
        )
            .write(to: directory.appendingPathComponent("insights_bundle.json"), options: .atomic)
    }

    @MainActor
    private func exportConsentState() async -> InsightsConsentState {
        let healthKit = HealthKitService.shared
        if healthKit.isAvailable {
            await healthKit.syncAuthorizationState()
        }

        let whoop = WHOOPService.shared
        return InsightsConsentState(
            appleHealthEnabled: settings.healthKitEnabled,
            appleHealthAvailable: healthKit.isAvailable,
            appleHealthAuthorized: healthKit.isAuthorized,
            whoopEnabled: settings.whoopEnabled && WHOOPService.isEnabled,
            whoopConnected: whoop.isConnected
        )
    }

    private func buildStudioEventsCSV(using repo: SessionRepository, sessionDates: [String]) -> String {
        var rows = ["event_type,occurred_at_utc,details,device_time"]
        for sessionDate in sessionDates {
            let doseEvents = repo.fetchDoseEvents(forSessionDate: sessionDate)
                .map { event in
                    studioCSVRow(
                        eventType: normalizedBundleEventType(event.eventType),
                        timestamp: event.timestamp,
                        details: event.metadata,
                        deviceTime: sessionDate
                    )
                }
            let sleepEvents = repo.fetchSleepEvents(for: sessionDate)
                .map { event in
                    studioCSVRow(
                        eventType: normalizedBundleEventType(event.eventType),
                        timestamp: event.timestamp,
                        details: event.notes,
                        deviceTime: sessionDate
                    )
                }
            rows.append(contentsOf: (doseEvents + sleepEvents).sorted())
        }
        return rows.joined(separator: "\n") + "\n"
    }

    @MainActor
    private func buildStudioSessionsCSV(
        using repo: SessionRepository,
        sessionDates: [String],
        enrichmentBySessionDate: [String: StudioExportSessionContext]
    ) -> String {
        var rows = ["started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes"]
        for sessionDate in sessionDates {
            guard let doseLog = repo.fetchDoseLog(forSession: sessionDate) else { continue }
            let enrichment = enrichmentBySessionDate[sessionDate]
            let startedUTC = doseLog.dose1Time
            let endedUTC = doseLog.dose2Time
            let adherenceFlag = doseLog.dose2Skipped ? "missed" : (doseLog.intervalMinutes ?? 0) > 240 ? "late" : "ok"
            let row = [
                AppFormatters.iso8601Fractional.string(from: startedUTC),
                endedUTC.map(AppFormatters.iso8601Fractional.string(from:)) ?? "",
                String(settings.targetIntervalMinutes),
                doseLog.intervalMinutes.map(String.init) ?? "",
                adherenceFlag,
                numericCSVField(enrichment?.whoop?.recoveryScore.map { Double(Int($0.rounded())) }),
                numericCSVField(enrichment?.healthKit?.averageHeartRate),
                numericCSVField(enrichment?.whoop?.sleepEfficiency),
                ""
            ].map(csvField).joined(separator: ",")
            rows.append(row)
        }
        return rows.joined(separator: "\n") + "\n"
    }

    @MainActor
    private func collectStudioExportEnrichment(sessionDates: [String]) async -> [String: StudioExportSessionContext] {
        guard !sessionDates.isEmpty else { return [:] }

        let whoopBySessionDate = await fetchWHOOPSummariesForExport(sessionDates: sessionDates)
        var enrichmentBySessionDate: [String: StudioExportSessionContext] = [:]

        for sessionDate in sessionDates {
            let healthKit = await fetchAppleHealthSummaryForExport(sessionDate: sessionDate)
            let whoop = whoopBySessionDate[sessionDate]

            guard healthKit != nil || whoop != nil else { continue }
            enrichmentBySessionDate[sessionDate] = StudioExportSessionContext(
                healthKit: healthKit,
                whoop: whoop
            )
        }

        return enrichmentBySessionDate
    }

    @MainActor
    private func fetchAppleHealthSummaryForExport(sessionDate: String) async -> InsightsAppleHealthSummary? {
        let healthKit = HealthKitService.shared
        guard settings.healthKitEnabled, healthKit.isAvailable else {
            return nil
        }

        await healthKit.syncAuthorizationState()
        guard healthKit.isAuthorized,
              let queryRange = studioQueryRange(for: sessionDate) else {
            return nil
        }

        do {
            async let segmentsTask = healthKit.fetchSegmentsForTimeline(from: queryRange.start, to: queryRange.end)
            async let biometricsTask = healthKit.fetchNightBiometrics(from: queryRange.start, to: queryRange.end)

            let segments = try await segmentsTask
            let biometrics = try await biometricsTask
            let sortedSegments = segments.sorted { $0.start < $1.start }

            guard !sortedSegments.isEmpty || biometrics.hasAnyMetric else {
                return nil
            }

            let bedTime = sortedSegments.first(where: { $0.stage == .inBed })?.start
            let sleepOnset = sortedSegments.first(where: { $0.stage.isAsleep })?.start
            let finalWake = sortedSegments.last?.end
            let totalSleepMinutes = sortedSegments
                .filter { $0.stage.isAsleep }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let awakeSegments = sortedSegments.filter { $0.stage == .awake }
            let wakeCount = awakeSegments.count
            let awakeMinutes = awakeSegments.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let inBedMinutes = sortedSegments
                .filter { $0.stage == .inBed }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let coreSleepMinutes = sortedSegments
                .filter { $0.stage == .asleepCore || $0.stage == .asleep }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let deepSleepMinutes = sortedSegments
                .filter { $0.stage == .asleepDeep }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let remSleepMinutes = sortedSegments
                .filter { $0.stage == .asleepREM }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }

            var firstWake: Date?
            var foundSleep = false
            for segment in sortedSegments {
                if segment.stage.isAsleep {
                    foundSleep = true
                } else if foundSleep && segment.stage == .awake {
                    firstWake = segment.start
                    break
                }
            }

            let ttfwMinutes = (sleepOnset != nil && firstWake != nil)
                ? firstWake!.timeIntervalSince(sleepOnset!) / 60
                : nil
            let wasoMinutes = sortedSegments.reduce(0.0) { partial, segment in
                guard segment.stage == .awake,
                      let sleepOnset,
                      let finalWake,
                      segment.start >= sleepOnset,
                      segment.end <= finalWake else {
                    return partial
                }
                return partial + segment.end.timeIntervalSince(segment.start) / 60
            }

            return InsightsAppleHealthSummary(
                totalSleepMinutes: totalSleepMinutes,
                ttfwMinutes: ttfwMinutes,
                wakeCount: wakeCount,
                awakeMinutes: awakeMinutes,
                wakeAfterSleepOnsetMinutes: wasoMinutes,
                inBedMinutes: inBedMinutes,
                coreSleepMinutes: coreSleepMinutes,
                deepSleepMinutes: deepSleepMinutes,
                remSleepMinutes: remSleepMinutes,
                bedTimeUTC: bedTime,
                sleepOnsetUTC: sleepOnset,
                finalWakeUTC: finalWake,
                averageHeartRate: biometrics.averageHeartRate,
                respiratoryRate: biometrics.respiratoryRate,
                hrvMs: biometrics.hrvMs,
                restingHeartRate: biometrics.restingHeartRate,
                sources: Array(Set(sortedSegments.map(\.source))).sorted()
            )
        } catch {
            settingsActionsLog.warning("Apple Health export enrichment failed for \(sessionDate, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor
    private func fetchWHOOPSummariesForExport(sessionDates: [String]) async -> [String: InsightsWHOOPSummary] {
        let whoop = WHOOPService.shared
        guard WHOOPService.isEnabled,
              settings.whoopEnabled,
              whoop.isConnected,
              let firstSessionDate = sessionDates.first,
              let lastSessionDate = sessionDates.last,
              let firstRange = studioQueryRange(for: firstSessionDate),
              let lastRange = studioQueryRange(for: lastSessionDate) else {
            return [:]
        }

        do {
            let summaries = try await whoop.fetchNightSummaries(from: firstRange.start, to: lastRange.end)
            var mapped: [String: InsightsWHOOPSummary] = [:]

            for summary in summaries {
                let key = AppFormatters.sessionDate.string(from: summary.date)
                if mapped[key] == nil {
                    mapped[key] = exportWHOOPSummary(from: summary)
                }
            }

            return mapped
        } catch {
            settingsActionsLog.warning("WHOOP export enrichment failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func exportWHOOPSummary(from summary: WHOOPNightSummary) -> InsightsWHOOPSummary {
        InsightsWHOOPSummary(
            sleepId: summary.sleepId,
            totalSleepMinutes: summary.totalSleepMinutes,
            remMinutes: summary.remMinutes,
            deepMinutes: summary.deepMinutes,
            lightMinutes: summary.lightMinutes,
            awakeMinutes: summary.awakeMinutes,
            inBedMinutes: summary.inBedMinutes,
            disturbanceCount: summary.disturbanceCount,
            sleepEfficiency: summary.sleepEfficiency,
            sleepPerformance: summary.sleepPerformance,
            sleepConsistency: summary.sleepConsistency,
            respiratoryRate: summary.respiratoryRate,
            recoveryScore: summary.recoveryScore,
            hrvMs: summary.hrvMs,
            restingHeartRate: summary.restingHeartRate,
            sleepNeedBaselineMinutes: summary.sleepNeedBaselineMinutes,
            sleepNeedDebtMinutes: summary.sleepNeedDebtMinutes,
            sleepNeedStrainMinutes: summary.sleepNeedStrainMinutes,
            sleepNeedNapMinutes: summary.sleepNeedNapMinutes,
            spo2Percentage: summary.spo2Percentage,
            skinTempCelsius: summary.skinTempCelsius
        )
    }

    private func studioQueryRange(for sessionDate: String) -> (start: Date, end: Date)? {
        guard let nightDate = AppFormatters.sessionDate.date(from: sessionDate),
              let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else {
            return nil
        }

        return (
            start: eveningAnchorDate(for: nightDate, hour: 18),
            end: eveningAnchorDate(for: nextDay, hour: 12)
        )
    }

    private func buildStudioInventoryCSV() -> String {
        "as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes\n"
    }

    private func exportSessionContext(
        sessionDate: String,
        sessionId: String,
        doseLog: StoredDoseLog?,
        doseEvents: [DoseCore.StoredDoseEvent],
        preSleepLog: StoredPreSleepLog?,
        morningCheckIn: StoredMorningCheckIn?,
        sleepEvents: [StoredSleepEvent],
        precomputedAlarmContext: InsightsAlarmContext? = nil
    ) -> InsightsSessionContext? {
        guard doseLog != nil || preSleepLog != nil || morningCheckIn != nil || !sleepEvents.isEmpty || !doseEvents.isEmpty else {
            return nil
        }

        let answers = preSleepLog?.answers
        let timingContext = morningCheckIn?.resolvedTimingContext
        let wakeFinal = sleepEvents
            .filter { normalizedEventType($0.eventType) == "wake_final" }
            .sorted { $0.timestamp < $1.timestamp }
            .last?
            .timestamp
        let snoozeCount = doseLog?.snoozeCount ?? 0
        let wakeSignal: String
        if ["natural"].contains(timingContext?.wakeType) {
            wakeSignal = "likely_natural"
        } else if ["alarm", "alarm_then_snooze"].contains(timingContext?.wakeType) || snoozeCount > 0 {
            wakeSignal = "alarm_assisted"
        } else if wakeFinal != nil {
            wakeSignal = "likely_natural"
        } else {
            wakeSignal = "unknown"
        }

        let scheduleMarkers = collectScheduleMarkers(from: answers)
        let nextMorningWeekday = nextMorningWeekdayIndex(for: sessionDate)
        let alarmContext = precomputedAlarmContext ?? exportAlarmContext(forSessionId: sessionId)
        let dose2Outcome = exportDose2OutcomeContext(from: doseEvents, timingContext: timingContext)

        let scheduleInfo = scheduledWakeInfo(for: sessionDate)
        let previousScheduleInfo = adjacentScheduledWakeInfo(for: sessionDate, dayOffset: -1)
        let nextScheduleInfo = adjacentScheduledWakeInfo(for: sessionDate, dayOffset: 1)

        return InsightsSessionContext(
            nextMorningWeekdayIndex: nextMorningWeekday,
            nextMorningIsWeekend: nextMorningWeekday == 1 || nextMorningWeekday == 7,
            scheduledWakeByUTC: scheduleInfo?.wakeDate,
            scheduledWakeMinutesAfterMidnight: scheduleInfo?.minutesAfterMidnight,
            scheduleDayType: scheduleInfo?.dayType,
            previousScheduleDayType: previousScheduleInfo?.dayType,
            nextScheduleDayType: nextScheduleInfo?.dayType,
            explicitNightType: timingContext?.nightType,
            firstNightOffAfterWorkBlock: timingContext?.firstNightOffAfterWorkBlock ?? false,
            explicitWakeType: timingContext?.wakeType,
            explicitNextDayDemand: timingContext?.nextDayDemand,
            explicitDose2WakeMethod: timingContext?.dose2WakeMethod,
            explicitBackToSleepDuration: timingContext?.backToSleepDuration,
            alarm: alarmContext,
            dose2Outcome: dose2Outcome,
            wakeSignal: wakeSignal,
            wakeFinalLoggedAtUTC: wakeFinal,
            snoozeCount: snoozeCount,
            scheduleMarkers: scheduleMarkers,
            wakeRequirement: timingContext?.wakeRequirement,
            shiftStartAtUTC: timingContext?.shiftStartAtUTC,
            shiftEndAtUTC: timingContext?.shiftEndAtUTC,
            nextRequiredWakeAtUTC: timingContext?.nextRequiredWakeAtUTC,
            commuteMinutes: timingContext?.commuteMinutes,
            lateMealType: answers?.lateMeal?.rawValue,
            lateMealEndedAtUTC: answers?.lateMealEndedAt,
            lateMealMinutesBeforeDose1: minutesBetween(answers?.lateMealEndedAt, and: doseLog?.dose1Time),
            lateMealMinutesBeforeDose2: minutesBetween(answers?.lateMealEndedAt, and: doseLog?.dose2Time),
            caffeineLastIntakeAtUTC: answers?.caffeineLastIntakeAt,
            caffeineMinutesBeforeDose1: minutesBetween(answers?.caffeineLastIntakeAt, and: doseLog?.dose1Time),
            alcoholLastDrinkAtUTC: answers?.alcoholLastDrinkAt,
            alcoholMinutesBeforeDose1: minutesBetween(answers?.alcoholLastDrinkAt, and: doseLog?.dose1Time),
            exerciseLastAtUTC: answers?.exerciseLastAt,
            exerciseMinutesBeforeDose1: minutesBetween(answers?.exerciseLastAt, and: doseLog?.dose1Time),
            napLastEndAtUTC: answers?.napLastEndAt,
            napMinutesBeforeDose1: minutesBetween(answers?.napLastEndAt, and: doseLog?.dose1Time),
            screensLastUsedAtUTC: answers?.screensLastUsedAt,
            screenMinutesBeforeDose1: minutesBetween(answers?.screensLastUsedAt, and: doseLog?.dose1Time)
        )
    }

    private func exportDose2OutcomeContext(
        from doseEvents: [DoseCore.StoredDoseEvent],
        timingContext: MorningTimingContext?
    ) -> InsightsDose2OutcomeContext? {
        let sortedEvents = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let primaryDose2Event = sortedEvents.first { normalizedEventType($0.eventType) == "dose2" }
        let skipEvent = sortedEvents.last { normalizedEventType($0.eventType) == "dose2_skipped" }
        let hasExtraDose = sortedEvents.contains { normalizedEventType($0.eventType) == "extra_dose" }

        let dose2Metadata = jsonDictionary(from: primaryDose2Event?.metadata)
        let skipMetadata = jsonDictionary(from: skipEvent?.metadata)
        let takenSource = stringValue(from: dose2Metadata["source"])
        let takenAmountMg = intValue(from: dose2Metadata["amount_mg"])
        let takenEarly = boolValue(from: dose2Metadata["is_early"])
        let takenLate = boolValue(from: dose2Metadata["is_late"])
        let liveTakenReason = stringValue(from: dose2Metadata["reason"])
        let liveTakenReasonNotes = stringValue(from: dose2Metadata["reason_notes"])
        let morningTakenReason = normalizedOptionalString(timingContext?.dose2TakenReason)
        let morningTakenReasonNotes = normalizedOptionalString(timingContext?.dose2ReasonNotes)
        let takenReason = morningTakenReason ?? liveTakenReason
        let takenReasonNotes = morningTakenReasonNotes ?? liveTakenReasonNotes
        let liveSkipReason = stringValue(from: skipMetadata["reason"])
        let liveSkipReasonNotes = stringValue(from: skipMetadata["reason_notes"])
        let morningSkipReason = normalizedOptionalString(timingContext?.dose2SkippedReason)
        let morningSkipReasonNotes = normalizedOptionalString(timingContext?.dose2ReasonNotes)
        let skipReason = morningSkipReason ?? liveSkipReason
        let skipReasonNotes = morningSkipReasonNotes ?? liveSkipReasonNotes
        let skipSource = stringValue(from: skipMetadata["source"])
        let reasonMismatch = hasValueMismatch(liveTakenReason, morningTakenReason)
            || hasValueMismatch(liveSkipReason, morningSkipReason)

        guard
            primaryDose2Event != nil
                || skipEvent != nil
                || hasExtraDose
                || takenReason != nil
                || skipReason != nil
                || takenReasonNotes != nil
                || skipReasonNotes != nil
                || reasonMismatch
        else {
            return nil
        }

        return InsightsDose2OutcomeContext(
            takenSource: takenSource,
            takenAmountMg: takenAmountMg,
            takenEarly: takenEarly,
            takenLate: takenLate,
            liveTakenReason: liveTakenReason,
            liveTakenReasonNotes: liveTakenReasonNotes,
            morningTakenReason: morningTakenReason,
            morningTakenReasonNotes: morningTakenReasonNotes,
            takenReason: takenReason,
            takenReasonNotes: takenReasonNotes,
            hasExtraDose: hasExtraDose,
            liveSkipReason: liveSkipReason,
            liveSkipReasonNotes: liveSkipReasonNotes,
            morningSkipReason: morningSkipReason,
            morningSkipReasonNotes: morningSkipReasonNotes,
            skipReason: skipReason,
            skipReasonNotes: skipReasonNotes,
            skipSource: skipSource,
            reasonMismatch: reasonMismatch
        )
    }

    private func exportAlarmContext(forSessionId sessionId: String) -> InsightsAlarmContext? {
        let entries = loadDiagnosticEntries(forSessionId: sessionId)
        guard !entries.isEmpty else { return nil }

        let mainAlarmId = "dosetap_dose2_alarm"
        let followUpPrefix = "dosetap_followup_"
        let alarmNotificationIds = Set(entries.compactMap { entry -> String? in
            let notificationId = entry.notificationId
            if notificationId == mainAlarmId || notificationId?.hasPrefix(followUpPrefix) == true {
                return notificationId
            }
            return nil
        })

        let scheduledForUTC = entries
            .filter { $0.event == .alarmScheduled && $0.alarmId == mainAlarmId }
            .compactMap(\.scheduledForTime)
            .min()
        let firstFireAtUTC = entries
            .filter { $0.event == .notificationDelivered && alarmNotificationIds.contains($0.notificationId ?? "") }
            .map(\.ts)
            .min()
        let acknowledgementEntry = entries
            .filter {
                ($0.event == .notificationTapped || $0.event == .notificationDismissed)
                    && alarmNotificationIds.contains($0.notificationId ?? "")
            }
            .sorted { $0.ts < $1.ts }
            .first
        let followUpDeliveredCount = entries.filter {
            $0.event == .notificationDelivered && ($0.notificationId?.hasPrefix(followUpPrefix) ?? false)
        }.count

        guard scheduledForUTC != nil || firstFireAtUTC != nil || acknowledgementEntry != nil || followUpDeliveredCount > 0 else {
            return nil
        }

        return InsightsAlarmContext(
            scheduledForUTC: scheduledForUTC,
            firstFireAtUTC: firstFireAtUTC,
            acknowledgedAtUTC: acknowledgementEntry?.ts,
            acknowledgementAction: normalizedNotificationAction(entry: acknowledgementEntry),
            followUpDeliveredCount: followUpDeliveredCount
        )
    }

    private func loadDiagnosticEntries(forSessionId sessionId: String) -> [DiagnosticLogEntry] {
        let root = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("diagnostics/sessions", isDirectory: true)
        guard let fileURL = root?.appendingPathComponent(sessionId, isDirectory: true).appendingPathComponent("events.jsonl"),
              FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(DiagnosticLogEntry.self, from: data)
            }
    }

    private func normalizedNotificationAction(entry: DiagnosticLogEntry?) -> String? {
        guard let entry else { return nil }
        if entry.event == .notificationDismissed {
            return "dismissed"
        }

        switch entry.notificationActionId {
        case "dosetap_alarm_stop":
            return "stop"
        case "dosetap_alarm_snooze":
            return "snooze"
        case UNNotificationDefaultActionIdentifier:
            return "opened_app"
        case UNNotificationDismissActionIdentifier:
            return "dismissed"
        case let action?:
            return action
        default:
            return "acknowledged"
        }
    }

    private func jsonDictionary(from jsonString: String?) -> [String: Any] {
        guard
            let jsonString,
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return normalizedOptionalString(string)
        default:
            return nil
        }
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func symptomBurdenValue(from value: Any?) -> String? {
        stringValue(from: value)
    }

    private func derivedPainBurden(from physical: [String: Any]) -> String? {
        if let burden = symptomBurdenValue(from: physical["painBurden"]) {
            return burden
        }
        if let isMigraine = physical["isMigraine"] as? Bool, isMigraine {
            return "extreme"
        }
        if let headacheSeverity = stringValue(from: physical["headacheSeverity"]), headacheSeverity.lowercased() == "migraine" {
            return "extreme"
        }
        var intensities: [Int] = []
        if let entries = physical["painEntries"] as? [[String: Any]] {
            intensities.append(contentsOf: entries.compactMap { intValue(from: $0["intensity"]) })
        }
        if let painSeverity = intValue(from: physical["painSeverity"]) {
            intensities.append(painSeverity)
        }
        let maxIntensity = intensities.max() ?? 0
        switch maxIntensity {
        case 9...:
            return "extreme"
        case 7...8:
            return "severe"
        case 4...6:
            return "moderate"
        case 1...3:
            return "mild"
        default:
            let hasAnyPainSignal =
                boolValue(from: physical["hasHeadache"])
                || stringValue(from: physical["muscleStiffness"]).map { $0.lowercased() != "none" } == true
                || stringValue(from: physical["muscleSoreness"]).map { $0.lowercased() != "none" } == true
            return hasAnyPainSignal ? "mild" : nil
        }
    }

    private func derivedCongestionBurden(from respiratory: [String: Any]) -> String? {
        if let burden = symptomBurdenValue(from: respiratory["congestionBurden"]) {
            return burden
        }
        let congestion = stringValue(from: respiratory["congestion"])?.lowercased()
        let sinusPressure = stringValue(from: respiratory["sinusPressure"])?.lowercased()
        let sickness = stringValue(from: respiratory["sicknessLevel"])?.lowercased()

        if sickness == "actively sick" || sinusPressure == "severe" {
            return "severe"
        }
        if congestion == "both" || sinusPressure == "moderate" || sickness == "coming down with something" {
            return "moderate"
        }
        if congestion == "stuffy nose" || congestion == "runny nose" || sinusPressure == "mild" || sickness == "recovering" {
            return "mild"
        }
        return nil
    }

    private func hasValueMismatch(_ liveValue: String?, _ morningValue: String?) -> Bool {
        guard
            let liveValue = normalizedOptionalString(liveValue),
            let morningValue = normalizedOptionalString(morningValue)
        else {
            return false
        }
        return liveValue != morningValue
    }

    private func intValue(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func boolValue(from value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["true", "1", "yes"].contains(string.lowercased())
        default:
            return false
        }
    }

    private func minutesBetween(_ earlier: Date?, and later: Date?) -> Int? {
        guard let earlier, let later else { return nil }
        let value = Int(later.timeIntervalSince(earlier) / 60)
        return value >= 0 ? value : nil
    }

    private func normalizedEventType(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func collectScheduleMarkers(from answers: PreSleepLogAnswers?) -> [String] {
        guard let answers else { return [] }

        var markers = answers.resolvedStressDrivers
            .map(\.rawValue)
            .filter { $0.localizedCaseInsensitiveContains("schedule") }

        if let laterReason = answers.laterReason?.rawValue,
           laterReason.localizedCaseInsensitiveContains("schedule") {
            markers.append(laterReason)
        }

        return Array(Set(markers)).sorted()
    }

    private func nextMorningWeekdayIndex(for sessionDate: String) -> Int {
        let calendar = Calendar.current
        guard let nightDate = AppFormatters.sessionDate.date(from: sessionDate),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: nightDate) else {
            return 0
        }
        return calendar.component(.weekday, from: nextDay)
    }

    private func scheduledWakeInfo(for sessionDate: String) -> (wakeDate: Date, minutesAfterMidnight: Int, dayType: String)? {
        let store = SleepPlanStore.shared
        let wakeDate = store.wakeByDate(for: sessionDate, tz: .current)
        let entry = store.schedule.entry(for: nextMorningWeekdayIndex(for: sessionDate))
        guard entry.enabled else {
            return nil
        }

        let enabledEntries = store.schedule.entries.filter(\.enabled)
        let wakeMinutes = entry.wakeByHour * 60 + entry.wakeByMinute
        let uniqueWakeMinutes = Array(Set(enabledEntries.map { $0.wakeByHour * 60 + $0.wakeByMinute })).sorted()
        let dayType: String
        if uniqueWakeMinutes.count >= 2, let earliest = uniqueWakeMinutes.first, let latest = uniqueWakeMinutes.last {
            let threshold = Int((Double(earliest + latest) / 2.0).rounded())
            dayType = wakeMinutes <= threshold ? "worklike" : "offlike"
        } else {
            dayType = "uniform"
        }

        return (wakeDate, wakeMinutes, dayType)
    }

    private func adjacentScheduledWakeInfo(for sessionDate: String, dayOffset: Int) -> (wakeDate: Date, minutesAfterMidnight: Int, dayType: String)? {
        guard let date = AppFormatters.sessionDate.date(from: sessionDate),
              let adjacent = Calendar.current.date(byAdding: .day, value: dayOffset, to: date) else {
            return nil
        }
        return scheduledWakeInfo(for: AppFormatters.sessionDate.string(from: adjacent))
    }

    private func exportRawEvents(
        doseEvents: [DoseCore.StoredDoseEvent],
        sleepEvents: [StoredSleepEvent],
        sessionDate: String
    ) -> [InsightsBundleEvent] {
        let rawDoseEvents = doseEvents.map { event in
            let metadata = jsonDictionary(from: event.metadata)
            return InsightsBundleEvent(
                kind: "dose",
                eventType: event.eventType,
                occurredAtUTC: event.timestamp,
                details: event.metadata,
                source: stringValue(from: metadata["source"]) ?? "manual",
                deviceTime: sessionDate
            )
        }

        let rawSleepEvents = sleepEvents.map { event in
            InsightsBundleEvent(
                kind: "sleep",
                eventType: event.eventType,
                occurredAtUTC: event.timestamp,
                details: event.notes,
                source: "manual",
                deviceTime: sessionDate
            )
        }

        return (rawDoseEvents + rawSleepEvents).sorted { lhs, rhs in
            lhs.occurredAtUTC < rhs.occurredAtUTC
        }
    }

    private func exportNormalizedEvents(from rawEvents: [InsightsBundleEvent]) -> [InsightsBundleEvent] {
        rawEvents.map { event in
            InsightsBundleEvent(
                kind: event.kind,
                eventType: normalizedBundleEventType(event.eventType),
                occurredAtUTC: event.occurredAtUTC,
                details: event.details,
                source: normalizedOptionalString(event.source),
                deviceTime: event.deviceTime
            )
        }
    }

    private func buildMetricProvenance(
        doseLog: StoredDoseLog?,
        doseEvents: [DoseCore.StoredDoseEvent],
        sleepEvents: [StoredSleepEvent],
        preSleepLog: StoredPreSleepLog?,
        morningCheckIn: StoredMorningCheckIn?,
        healthKit: InsightsAppleHealthSummary?,
        whoop: InsightsWHOOPSummary?
    ) -> [String: String] {
        let sortedDoseEvents = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let dose1Metadata = jsonDictionary(from: sortedDoseEvents.first(where: { normalizedEventType($0.eventType) == "dose1" })?.metadata)
        let dose2Metadata = jsonDictionary(from: sortedDoseEvents.first(where: { normalizedEventType($0.eventType) == "dose2" })?.metadata)
        let skipMetadata = jsonDictionary(from: sortedDoseEvents.first(where: { normalizedEventType($0.eventType) == "dose2_skipped" })?.metadata)
        let timingContext = morningCheckIn?.resolvedTimingContext

        var provenance: [String: String] = [:]

        if doseLog?.dose1Time != nil {
            provenance["dose1_time"] = stringValue(from: dose1Metadata["source"]) ?? "manual"
        }
        if doseLog?.dose2Time != nil {
            provenance["dose2_time"] = stringValue(from: dose2Metadata["source"]) ?? "manual"
        }
        if doseLog?.dose2Skipped == true {
            provenance["dose2_skip"] = stringValue(from: skipMetadata["source"]) ?? "manual"
        }
        if doseLog?.intervalMinutes != nil {
            provenance["interval_minutes"] = "derived"
        }

        if morningCheckIn != nil {
            provenance["morning_sleep_quality"] = "manual"
            provenance["morning_readiness"] = "manual"
            provenance["morning_mental_clarity"] = "manual"
            provenance["sleep_inertia_duration"] = "manual"
            provenance["anxiety_burden"] = "manual"
            if let physical = morningCheckIn.flatMap({ jsonDictionary(from: $0.physicalSymptomsJson) }), derivedPainBurden(from: physical) != nil {
                provenance["pain_burden"] = "manual"
            }
            if let respiratory = morningCheckIn.flatMap({ jsonDictionary(from: $0.respiratorySymptomsJson) }), derivedCongestionBurden(from: respiratory) != nil {
                provenance["congestion_burden"] = "manual"
            }
            if let physical = morningCheckIn.flatMap({ jsonDictionary(from: $0.physicalSymptomsJson) }), symptomBurdenValue(from: physical["refluxBurden"]) != nil {
                provenance["reflux_burden"] = "manual"
            }
            if let physical = morningCheckIn.flatMap({ jsonDictionary(from: $0.physicalSymptomsJson) }), symptomBurdenValue(from: physical["restlessLegsBurden"]) != nil {
                provenance["restless_legs_burden"] = "manual"
            }
            if let physical = morningCheckIn.flatMap({ jsonDictionary(from: $0.physicalSymptomsJson) }), symptomBurdenValue(from: physical["bathroomUrgencyBurden"]) != nil {
                provenance["bathroom_urgency_burden"] = "manual"
            }
            if timingContext?.drivingConfidence != nil { provenance["driving_confidence"] = "manual" }
            if timingContext?.daytimeSleepiness != nil { provenance["daytime_sleepiness"] = "manual" }
            if timingContext?.cataplexyBurden != nil { provenance["cataplexy_burden"] = "manual" }
            if timingContext?.wakeRequirement != nil { provenance["wake_requirement"] = "manual" }
            if timingContext?.shiftStartAtUTC != nil || timingContext?.shiftEndAtUTC != nil { provenance["shift_window"] = "manual" }
            if timingContext?.nextRequiredWakeAtUTC != nil { provenance["next_required_wake"] = "manual" }
            if timingContext?.commuteMinutes != nil { provenance["commute_minutes"] = "manual" }
            if timingContext?.firstNightOffAfterWorkBlock == true { provenance["first_night_off_after_work_block"] = "manual" }
            if !(timingContext?.sleepDisorders.isEmpty ?? true) { provenance["sleep_disorder_context"] = "manual" }
            if timingContext?.coMedicationNotes != nil { provenance["co_medication_context"] = "manual" }
            if timingContext?.pharmacogenomicFastMetabolizer == true || timingContext?.pharmacogenomicClinicianReviewed == true || timingContext?.pharmacogenomicNotes != nil {
                provenance["pharmacogenomic_context"] = "manual"
            }
        }

        if preSleepLog != nil {
            provenance["pre_sleep_stress"] = "manual"
            provenance["body_pain"] = "manual"
            provenance["late_meal_timing"] = "manual"
            provenance["late_meal_type"] = "manual"
            provenance["caffeine_timing"] = "manual"
            provenance["alcohol_timing"] = "manual"
            provenance["exercise_timing"] = "manual"
            provenance["nap_timing"] = "manual"
            provenance["screen_timing"] = "manual"
        }

        if let healthKit {
            provenance["total_sleep_minutes"] = "healthkit"
            provenance["ttfw_minutes"] = "healthkit"
            provenance["wake_count"] = "healthkit"
            provenance["awake_minutes"] = "healthkit"
            provenance["wake_after_sleep_onset_minutes"] = "healthkit"
            provenance["in_bed_minutes"] = "healthkit"
            provenance["core_sleep_minutes"] = "healthkit"
            provenance["deep_sleep_minutes"] = "healthkit"
            provenance["rem_sleep_minutes"] = "healthkit"
            if healthKit.averageHeartRate != nil { provenance["average_heart_rate"] = "healthkit" }
        } else if !sleepEvents.isEmpty {
            provenance["total_sleep_minutes"] = "derived"
        }

        if let whoop {
            provenance["sleep_efficiency"] = "whoop"
            provenance["sleep_performance"] = "whoop"
            provenance["sleep_consistency"] = "whoop"
            provenance["whoop_recovery"] = "whoop"
            provenance["wake_disruption_count"] = "whoop"
            provenance["light_sleep_minutes"] = "whoop"
            provenance["sleep_need_baseline_minutes"] = "whoop"
            provenance["sleep_need_debt_minutes"] = "whoop"
            provenance["sleep_need_strain_minutes"] = "whoop"
            provenance["sleep_need_nap_minutes"] = "whoop"
            if healthKit == nil {
                provenance["total_sleep_minutes"] = "whoop"
                provenance["awake_minutes"] = "whoop"
                provenance["in_bed_minutes"] = "whoop"
                provenance["deep_sleep_minutes"] = "whoop"
                provenance["rem_sleep_minutes"] = "whoop"
            }
            if whoop.hrvMs != nil { provenance["hrv_ms"] = "whoop" }
            if whoop.respiratoryRate != nil { provenance["respiratory_rate"] = "whoop" }
            if whoop.restingHeartRate != nil { provenance["resting_heart_rate"] = "whoop" }
            if whoop.spo2Percentage != nil { provenance["spo2_percentage"] = "whoop" }
            if whoop.skinTempCelsius != nil { provenance["skin_temp_celsius"] = "whoop" }
        } else if let healthKit {
            provenance["wake_disruption_count"] = "healthkit"
            if healthKit.hrvMs != nil { provenance["hrv_ms"] = "healthkit" }
            if healthKit.respiratoryRate != nil { provenance["respiratory_rate"] = "healthkit" }
            if healthKit.restingHeartRate != nil { provenance["resting_heart_rate"] = "healthkit" }
        }
        if !sleepEvents.isEmpty {
            provenance["wake_signal"] = "derived"
        }

        return provenance
    }

    private func buildSessionDataQualityFlags(
        doseLog: StoredDoseLog?,
        doseEvents: [DoseCore.StoredDoseEvent],
        sleepEvents: [StoredSleepEvent]
    ) -> [String] {
        let sortedDoseEvents = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let dose1Events = sortedDoseEvents.filter { normalizedEventType($0.eventType) == "dose1" }
        let dose2Events = sortedDoseEvents.filter { normalizedEventType($0.eventType) == "dose2" }
        let skippedEvents = sortedDoseEvents.filter { normalizedEventType($0.eventType) == "dose2_skipped" }
        let lightsOutEvents = sleepEvents.filter { normalizedBundleEventType($0.eventType) == "lights_out" }
        let wakeFinalEvents = sleepEvents.filter { normalizedBundleEventType($0.eventType) == "wake_final" }

        var flags: Set<String> = []

        if let dose1Time = doseLog?.dose1Time,
           let dose2Time = doseLog?.dose2Time,
           dose2Time < dose1Time {
            flags.insert("Session ended before it started")
        }

        if let interval = doseLog?.intervalMinutes {
            if interval < 0 {
                flags.insert("Impossible negative interval")
            } else if interval > 360 {
                flags.insert("Extreme interval exceeds 360 minutes")
            }
        }

        if lightsOutEvents.count > 1 {
            flags.insert("Duplicate lights-out logs")
        }

        if wakeFinalEvents.count > 1 {
            flags.insert("Duplicate wake-final logs")
        }

        if !skippedEvents.isEmpty && !dose2Events.isEmpty {
            flags.insert("Conflicting Dose 2 taken and skipped events")
        }

        if doseLog?.dose2Skipped == false && doseLog?.dose2Time == nil && skippedEvents.isEmpty {
            flags.insert("Session marked ok but Dose 2 outcome is missing")
        }

        if let dose1Time = dose1Events.first?.timestamp,
           let dose2Time = dose2Events.first?.timestamp {
            let eventInterval = Int(dose2Time.timeIntervalSince(dose1Time) / 60)
            if eventInterval < 0 {
                flags.insert("Dose 2 event occurs before Dose 1")
            }

            if let sessionInterval = doseLog?.intervalMinutes,
               abs(eventInterval - sessionInterval) > 5 {
                flags.insert("Session interval mismatches event timeline")
            }
        }

        return Array(flags).sorted()
    }

    private func buildSessionExportExclusionReasons(
        doseLog: StoredDoseLog?,
        doseEvents: [DoseCore.StoredDoseEvent],
        sleepEvents: [StoredSleepEvent],
        morningCheckIn: StoredMorningCheckIn?
    ) -> [String] {
        var reasons = Set(buildSessionDataQualityFlags(doseLog: doseLog, doseEvents: doseEvents, sleepEvents: sleepEvents))

        if doseLog?.dose2Skipped == true {
            reasons.insert("Dose 2 skipped")
        }
        if doseLog?.dose2Time == nil, doseLog?.dose2Skipped == false {
            reasons.insert("Missing Dose 2 outcome")
        }
        if exportDose2OutcomeContext(from: doseEvents, timingContext: morningCheckIn?.resolvedTimingContext)?.reasonMismatch == true {
            reasons.insert("Dose 2 reason mismatch between live and morning logs")
        }
        if morningCheckIn == nil {
            reasons.insert("Missing morning check-in")
        }

        return Array(reasons).sorted()
    }

    private func buildBundleExportWarnings(sessions: [InsightsBundleSession]) -> [String] {
        guard !sessions.isEmpty else {
            return ["Export contains no sessions"]
        }

        var warnings: [String] = []
        let flaggedSessions = sessions.filter { !$0.dataQualityFlags.isEmpty }
        let missingProvenance = sessions.filter { ($0.metricProvenance ?? [:]).isEmpty }
        let missingWearables = sessions.filter { $0.healthKit == nil && $0.whoop == nil }
        let excludedSessions = sessions.filter { !($0.exportExclusionReasons?.isEmpty ?? true) }

        if !flaggedSessions.isEmpty {
            warnings.append("\(flaggedSessions.count) night(s) include session-level data-quality flags.")
        }
        if !missingProvenance.isEmpty {
            warnings.append("\(missingProvenance.count) night(s) have incomplete metric provenance.")
        }
        if !missingWearables.isEmpty {
            warnings.append("\(missingWearables.count) night(s) do not include Apple Health or WHOOP summaries.")
        }
        if !excludedSessions.isEmpty {
            warnings.append("\(excludedSessions.count) night(s) already carry export-side exclusion reasons.")
        }

        return warnings
    }

    private func normalizedBundleEventType(_ rawEventType: String) -> String {
        switch normalizedEventType(rawEventType) {
        case "dose1":
            return "dose1_taken"
        case "dose2":
            return "dose2_taken"
        case "dose2_skipped", "skip":
            return "dose2_skipped"
        case "dose2_snoozed", "snooze":
            return "dose2_snoozed"
        default:
            return EventType(rawEventType).canonicalString
        }
    }

    private func bundleVersionString() -> String? {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String

        switch (shortVersion, buildNumber) {
        case let (shortVersion?, buildNumber?) where shortVersion != buildNumber:
            return "\(shortVersion) (\(buildNumber))"
        case let (shortVersion?, _):
            return shortVersion
        case let (_, buildNumber?):
            return buildNumber
        default:
            return nil
        }
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

    private func numericCSVField(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
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
    let exportVersion: String?
    let appVersion: String?
    let exportedAtUTC: Date
    let timeZoneIdentifier: String?
    let localOffsetMinutes: Int?
    let consent: InsightsConsentState?
    let exportWarnings: [String]
    let sessions: [InsightsBundleSession]
}

private struct InsightsBundleEvent: Codable {
    let kind: String
    let eventType: String
    let occurredAtUTC: Date
    let details: String?
    let source: String?
    let deviceTime: String?
}

private struct InsightsSourceAvailability: Codable {
    let doseEvents: Bool
    let sleepEvents: Bool
    let preSleep: Bool
    let morningCheckIn: Bool
    let medications: Bool
    let healthKit: Bool
    let whoop: Bool
    let alarmDiagnostics: Bool
}

private struct InsightsConsentState: Codable {
    let appleHealthEnabled: Bool
    let appleHealthAvailable: Bool
    let appleHealthAuthorized: Bool
    let whoopEnabled: Bool
    let whoopConnected: Bool
}

private struct InsightsBundleSession: Codable {
    let sessionDate: String
    let dose1TimeUTC: Date?
    let dose2TimeUTC: Date?
    let rawEvents: [InsightsBundleEvent]
    let normalizedEvents: [InsightsBundleEvent]
    let sourceAvailability: InsightsSourceAvailability?
    let metricProvenance: [String: String]?
    let dataQualityFlags: [String]
    let exportExclusionReasons: [String]?
    let preSleep: InsightsPreSleepSummary?
    let morning: InsightsMorningSummary?
    let medications: [InsightsMedicationSummary]
    let context: InsightsSessionContext?
    let healthKit: InsightsAppleHealthSummary?
    let whoop: InsightsWHOOPSummary?
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
    let caffeineLastIntakeAtUTC: Date?
    let caffeineLastAmountMg: Int?
    let caffeineDailyTotalMg: Int?
    let alcohol: String?
    let alcoholLastDrinkAtUTC: Date?
    let alcoholLastAmountDrinks: Double?
    let alcoholDailyTotalDrinks: Double?
    let exercise: String?
    let exerciseLastAtUTC: Date?
    let exerciseDurationMinutes: Int?
    let napToday: String?
    let napCount: Int?
    let napTotalMinutes: Int?
    let napLastEndAtUTC: Date?
    let lateMeal: String?
    let lateMealEndedAtUTC: Date?
    let screensInBed: String?
    let screensLastUsedAtUTC: Date?
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
    let sleepTherapyDevice: String?
    let sleepTherapyCompliance: Int?
    let drivingConfidence: Int?
    let daytimeSleepiness: Int?
    let cataplexyBurden: String?
    let painBurden: String?
    let anxietyBurden: String?
    let congestionBurden: String?
    let refluxBurden: String?
    let restlessLegsBurden: String?
    let bathroomUrgencyBurden: String?
    let sleepDisorders: [String]
    let sleepDisorderNotes: String?
    let coMedicationNotes: String?
    let pharmacogenomicFastMetabolizer: Bool
    let pharmacogenomicClinicianReviewed: Bool
    let pharmacogenomicNotes: String?
    let firstNightOffAfterWorkBlock: Bool
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

private struct InsightsAppleHealthSummary: Codable {
    let totalSleepMinutes: Double
    let ttfwMinutes: Double?
    let wakeCount: Int
    let awakeMinutes: Double?
    let wakeAfterSleepOnsetMinutes: Double?
    let inBedMinutes: Double?
    let coreSleepMinutes: Double?
    let deepSleepMinutes: Double?
    let remSleepMinutes: Double?
    let bedTimeUTC: Date?
    let sleepOnsetUTC: Date?
    let finalWakeUTC: Date?
    let averageHeartRate: Double?
    let respiratoryRate: Double?
    let hrvMs: Double?
    let restingHeartRate: Double?
    let sources: [String]
}

private struct InsightsWHOOPSummary: Codable {
    let sleepId: String
    let totalSleepMinutes: Int
    let remMinutes: Int
    let deepMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
    let inBedMinutes: Int?
    let disturbanceCount: Int
    let sleepEfficiency: Double?
    let sleepPerformance: Double?
    let sleepConsistency: Double?
    let respiratoryRate: Double?
    let recoveryScore: Double?
    let hrvMs: Double?
    let restingHeartRate: Double?
    let sleepNeedBaselineMinutes: Int?
    let sleepNeedDebtMinutes: Int?
    let sleepNeedStrainMinutes: Int?
    let sleepNeedNapMinutes: Int?
    let spo2Percentage: Double?
    let skinTempCelsius: Double?
}

private struct InsightsSessionContext: Codable {
    let nextMorningWeekdayIndex: Int
    let nextMorningIsWeekend: Bool
    let scheduledWakeByUTC: Date?
    let scheduledWakeMinutesAfterMidnight: Int?
    let scheduleDayType: String?
    let previousScheduleDayType: String?
    let nextScheduleDayType: String?
    let explicitNightType: String?
    let firstNightOffAfterWorkBlock: Bool
    let explicitWakeType: String?
    let explicitNextDayDemand: String?
    let explicitDose2WakeMethod: String?
    let explicitBackToSleepDuration: String?
    let alarm: InsightsAlarmContext?
    let dose2Outcome: InsightsDose2OutcomeContext?
    let wakeSignal: String
    let wakeFinalLoggedAtUTC: Date?
    let snoozeCount: Int
    let scheduleMarkers: [String]
    let wakeRequirement: String?
    let shiftStartAtUTC: Date?
    let shiftEndAtUTC: Date?
    let nextRequiredWakeAtUTC: Date?
    let commuteMinutes: Int?
    let lateMealType: String?
    let lateMealEndedAtUTC: Date?
    let lateMealMinutesBeforeDose1: Int?
    let lateMealMinutesBeforeDose2: Int?
    let caffeineLastIntakeAtUTC: Date?
    let caffeineMinutesBeforeDose1: Int?
    let alcoholLastDrinkAtUTC: Date?
    let alcoholMinutesBeforeDose1: Int?
    let exerciseLastAtUTC: Date?
    let exerciseMinutesBeforeDose1: Int?
    let napLastEndAtUTC: Date?
    let napMinutesBeforeDose1: Int?
    let screensLastUsedAtUTC: Date?
    let screenMinutesBeforeDose1: Int?
}

private struct InsightsAlarmContext: Codable {
    let scheduledForUTC: Date?
    let firstFireAtUTC: Date?
    let acknowledgedAtUTC: Date?
    let acknowledgementAction: String?
    let followUpDeliveredCount: Int
}

private struct InsightsDose2OutcomeContext: Codable {
    let takenSource: String?
    let takenAmountMg: Int?
    let takenEarly: Bool
    let takenLate: Bool
    let liveTakenReason: String?
    let liveTakenReasonNotes: String?
    let morningTakenReason: String?
    let morningTakenReasonNotes: String?
    let takenReason: String?
    let takenReasonNotes: String?
    let hasExtraDose: Bool
    let liveSkipReason: String?
    let liveSkipReasonNotes: String?
    let morningSkipReason: String?
    let morningSkipReasonNotes: String?
    let skipReason: String?
    let skipReasonNotes: String?
    let skipSource: String?
    let reasonMismatch: Bool
}

private struct StudioExportSessionContext {
    let healthKit: InsightsAppleHealthSummary?
    let whoop: InsightsWHOOPSummary?
}
