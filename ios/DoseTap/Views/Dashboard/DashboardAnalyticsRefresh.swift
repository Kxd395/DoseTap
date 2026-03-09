import Foundation
import DoseCore

private enum DashboardDoseEventKind {
    case dose1
    case dose2
    case dose2Skipped
    case extraDose
    case other
}

private struct DashboardDerivedDoseMetrics {
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let extraDoseCount: Int
}

extension DashboardAnalyticsModel {
    func refresh(days: Int = 730) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(days: days)
        }
    }

    func performRefresh(days: Int) async {
        isLoading = true
        errorMessage = nil

        let sessions = sessionRepo.fetchRecentSessions(days: days)
        var sessionByKey: [String: SessionSummary] = [:]
        for session in sessions {
            sessionByKey[session.sessionDate] = session
        }

        var healthByKey: [String: HealthKitService.SleepNightSummary] = [:]
        if settings.healthKitEnabled {
            healthKit.checkAuthorizationStatus()
            if healthKit.isAuthorized {
                await healthKit.computeTTFWBaseline(days: max(14, min(days, 120)))
                guard !Task.isCancelled else { return }
                for summary in healthKit.sleepHistory {
                    let key = sessionRepo.sessionDateString(for: eveningAnchorDate(for: summary.date))
                    if healthByKey[key] == nil {
                        healthByKey[key] = summary
                    }
                }
            } else if let lastError = healthKit.lastError, !lastError.isEmpty {
                errorMessage = lastError
            }
        }

        var whoopByKey: [String: WHOOPNightSummary] = [:]
        if WHOOPService.isEnabled && settings.whoopEnabled && whoop.isConnected {
            do {
                let fetchDays = min(days, 30)
                let sleeps = try await whoop.fetchRecentSleep(nights: fetchDays)
                guard !Task.isCancelled else { return }
                for sleep in sleeps where sleep.scoreState?.uppercased() == "SCORED" {
                    let summary = sleep.toNightSummary()
                    let key = sessionRepo.sessionDateString(for: summary.date)
                    if whoopByKey[key] == nil {
                        whoopByKey[key] = summary
                    }
                }
                do {
                    let recoveries = try await whoop.fetchRecoveryData(
                        from: Calendar.current.date(byAdding: .day, value: -fetchDays, to: Date()) ?? Date(),
                        to: Date()
                    )
                    guard !Task.isCancelled else { return }
                    for recovery in recoveries {
                        if let sleepId = recovery.sleepId,
                           let existingKey = whoopByKey.first(where: { $0.value.sleepId == sleepId })?.key {
                            var updated = whoopByKey[existingKey]!
                            updated.recoveryScore = recovery.score?.recoveryScore
                            updated.hrvMs = recovery.score?.hrvMs
                            updated.restingHeartRate = recovery.score?.restingHeartRate
                            whoopByKey[existingKey] = updated
                        }
                    }
                } catch {
                    dashboardLogger.warning("WHOOP recovery fetch failed: \(error.localizedDescription)")
                }
            } catch {
                dashboardLogger.warning("WHOOP fetch failed: \(error.localizedDescription)")
            }
        }

        let calendar = Calendar.current
        let sessionKeys: [String] = (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
        }

        let aggregates: [DashboardNightAggregate] = sessionKeys.map { key in
            let summary = sessionByKey[key] ?? SessionSummary(sessionDate: key)
            let doseLog = sessionRepo.fetchDoseLog(forSession: key)
            let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: key)
            let derivedDose = deriveDoseMetrics(from: doseEvents)
            let events = sessionRepo.fetchSleepEvents(for: key).sorted { $0.timestamp < $1.timestamp }
            let duplicateClusters = buildStoredEventDuplicateGroups(events: events).count
            let sessionId = sessionRepo.fetchSessionId(forSessionDate: key) ?? key

            return DashboardNightAggregate(
                sessionDate: key,
                dose1Time: summary.dose1Time ?? doseLog?.dose1Time ?? derivedDose.dose1Time,
                dose2Time: summary.dose2Time ?? doseLog?.dose2Time ?? derivedDose.dose2Time,
                dose2Skipped: summary.dose2Skipped || doseLog?.dose2Skipped == true || derivedDose.dose2Skipped,
                snoozeCount: summary.snoozeCount,
                extraDoseCount: derivedDose.extraDoseCount,
                events: events,
                morningCheckIn: sessionRepo.fetchMorningCheckIn(for: key),
                preSleepLog: sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionId),
                healthSummary: healthByKey[key],
                whoopSummary: whoopByKey[key],
                duplicateClusterCount: duplicateClusters,
                napSummary: sessionRepo.napSummary(for: key)
            )
        }

        nights = aggregates.sorted { $0.sessionDate > $1.sessionDate }
        integrationStates = buildIntegrationStates(healthMatches: healthByKey.count, whoopMatches: whoopByKey.count)
        lastRefresh = Date()
        isLoading = false
    }

    private func normalizedDoseEventKind(_ rawType: String) -> DashboardDoseEventKind {
        let normalized = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            return .dose1
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken", "dose2_early", "dose_2_early", "dose2_late", "dose_2_late", "dose_2_(early)", "dose_2_(late)":
            return .dose2
        case "dose2_skipped", "dose_2_skipped", "dose2skipped", "dose_2_skipped_reason", "skip", "skipped":
            return .dose2Skipped
        case "extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken":
            return .extraDose
        default:
            return .other
        }
    }

    private func deriveDoseMetrics(from doseEvents: [DoseCore.StoredDoseEvent]) -> DashboardDerivedDoseMetrics {
        let sorted = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let dose1 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose1 }?.timestamp
        let dose2 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose2 }?.timestamp
        let skipped = sorted.contains { normalizedDoseEventKind($0.eventType) == .dose2Skipped }
        let extraCount = sorted.filter { normalizedDoseEventKind($0.eventType) == .extraDose }.count

        if dose1 == nil {
            let doseLike = sorted.filter {
                let kind = normalizedDoseEventKind($0.eventType)
                return kind == .dose1 || kind == .dose2 || kind == .extraDose
            }
            if let inferredDose1 = doseLike.first?.timestamp {
                let inferredDose2 = dose2 ?? (doseLike.count > 1 ? doseLike[1].timestamp : nil)
                return DashboardDerivedDoseMetrics(
                    dose1Time: inferredDose1,
                    dose2Time: inferredDose2,
                    dose2Skipped: skipped,
                    extraDoseCount: extraCount
                )
            }
        }

        return DashboardDerivedDoseMetrics(
            dose1Time: dose1,
            dose2Time: dose2,
            dose2Skipped: skipped,
            extraDoseCount: extraCount
        )
    }

    func buildIntegrationStates(healthMatches: Int, whoopMatches: Int = 0) -> [DashboardIntegrationState] {
        let healthState = DashboardIntegrationState(
            id: "healthkit",
            name: "Apple Health",
            status: settings.healthKitEnabled
                ? (healthKit.isAuthorized ? "Connected" : "Needs Authorization")
                : "Disabled",
            detail: settings.healthKitEnabled
                ? (healthKit.isAuthorized
                    ? "\(healthMatches) nights with sleep summaries mapped"
                    : (healthKit.lastError ?? "Enable read access for sleep analysis"))
                : "Enable in Settings to ingest sleep stages automatically.",
            color: settings.healthKitEnabled ? (healthKit.isAuthorized ? .green : .orange) : .gray
        )

        let whoopState: DashboardIntegrationState
        if !WHOOPService.isEnabled {
            whoopState = DashboardIntegrationState(
                id: "whoop",
                name: "WHOOP",
                status: "Not Connected",
                detail: "Connect WHOOP in Settings → Integrations to import sleep & recovery data.",
                color: .gray
            )
        } else {
            let whoopDetail: String
            if settings.whoopEnabled {
                if whoop.isConnected {
                    let syncInfo = whoop.lastSyncTime.map { " • Last sync \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                    whoopDetail = whoopMatches > 0
                        ? "\(whoopMatches) nights with sleep data\(syncInfo)"
                        : "Connected — no scored sleep data yet\(syncInfo)"
                } else {
                    whoopDetail = "Connect in Settings to ingest recovery/strain metrics."
                }
            } else {
                whoopDetail = "Turn on WHOOP integration in Settings when ready."
            }
            whoopState = DashboardIntegrationState(
                id: "whoop",
                name: "WHOOP",
                status: settings.whoopEnabled
                    ? (whoop.isConnected ? "Connected" : "Not Connected")
                    : "Disabled",
                detail: whoopDetail,
                color: settings.whoopEnabled ? (whoop.isConnected ? .green : .orange) : .gray
            )
        }

        let cloudState = DashboardIntegrationState(
            id: "cloud",
            name: "Cloud Sync",
            status: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? "Not Synced" : "Active")
                : "Disabled",
            detail: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil
                    ? cloudSync.statusMessage
                    : "Last sync \(cloudSync.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "") • \(cloudSync.statusMessage)")
                : "Cloud sync is unavailable in the local-first app target. Use the cloud-enabled staging target when validating deferred iCloud sync.",
            color: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? .orange : .green)
                : .gray
        )

        let exportState = DashboardIntegrationState(
            id: "export",
            name: "Share & Export",
            status: "Ready",
            detail: "Timeline review snapshot sharing is active (theme-aware export).",
            color: .teal
        )

        return [healthState, whoopState, cloudState, exportState]
    }
}
