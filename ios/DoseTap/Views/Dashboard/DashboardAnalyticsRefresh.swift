import Foundation
import DoseCore

struct DashboardDerivedDoseMetrics {
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let extraDoseCount: Int
    let snoozeCount: Int
}

extension DashboardAnalyticsModel {
    func refresh(days: Int = 730) {
        #if DEBUG && targetEnvironment(simulator)
        if loadDashboardUITestFixtureIfRequested() { return }
        #endif
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(days: days)
        }
    }

    func performRefresh(days: Int, includeProviders: Bool = true) async {
        let generation = UUID()
        refreshGeneration = generation
        isLoading = true
        defer { if refreshGeneration == generation { isLoading = false } }
        errorMessage = nil

        var healthByKey: [String: HealthKitService.SleepNightSummary] = [:]
        if includeProviders && settings.healthKitEnabled {
            await healthKit.syncAuthorizationState()
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
        if includeProviders && WHOOPService.isEnabled && settings.whoopEnabled && whoop.isConnected {
            do {
                let fetchDays = min(days, 30)
                let endDate = Date()
                let startDate = Calendar.current.date(byAdding: .day, value: -fetchDays, to: endDate) ?? endDate
                let summaries = try await whoop.fetchNightSummaries(from: startDate, to: endDate)
                guard !Task.isCancelled else { return }
                if let warning = whoop.lastError { errorMessage = warning }
                for summary in summaries {
                    let key = sessionRepo.sessionDateString(for: summary.date)
                    if summary.totalSleepMinutes > (whoopByKey[key]?.totalSleepMinutes ?? -1) {
                        whoopByKey[key] = summary
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "WHOOP sleep could not refresh. Local records are still available. Try Refresh again."
            }
        }

        let sessionKeys = Set(sessionRepo.allSessionDatesForSync())
            .union(healthByKey.keys).union(whoopByKey.keys).sorted(by: >)
        var aggregates: [DashboardNightAggregate] = []
        for key in sessionKeys {
            guard !Task.isCancelled else { return }
            let derivedDose = Self.deriveDoseMetrics(from: sessionRepo.fetchDoseEvents(forSessionDate: key))
            let events = sessionRepo.fetchSleepEvents(for: key).sorted { $0.timestamp < $1.timestamp }
            let duplicateClusters = buildStoredEventDuplicateGroups(events: events).count

            var aggregate = DashboardNightAggregate(
                sessionDate: key,
                dose1Time: derivedDose.dose1Time,
                dose2Time: derivedDose.dose2Time,
                dose2Skipped: derivedDose.dose2Skipped,
                snoozeCount: derivedDose.snoozeCount,
                extraDoseCount: derivedDose.extraDoseCount,
                events: events,
                morningCheckIn: sessionRepo.fetchMorningCheckIn(for: key),
                preSleepLog: sessionRepo.fetchPreSleepLog(forSessionDate: key),
                healthSummary: healthByKey[key],
                whoopSummary: whoopByKey[key],
                duplicateClusterCount: duplicateClusters,
                napSummary: sessionRepo.napSummary(for: key)
            )
            do { aggregate.outcome = try sessionRepo.nightOutcomeSnapshot(sessionDate: key).record?.answers }
            catch { aggregate.outcomeReadFailed = true }
            aggregates.append(aggregate)
            await Task.yield()
        }

        guard !Task.isCancelled, refreshGeneration == generation else { return }
        nights = aggregates.sorted { $0.sessionDate > $1.sessionDate }
        integrationStates = buildIntegrationStates(healthMatches: healthByKey.count, whoopMatches: whoopByKey.count)
        lastRefresh = Date()
        isLoading = false
    }

    static func deriveDoseMetrics(from doseEvents: [DoseCore.StoredDoseEvent]) -> DashboardDerivedDoseMetrics {
        let sorted = doseEvents.sorted { $0.timestamp < $1.timestamp }
        func events(_ kind: CanonicalDoseEventType) -> [DoseCore.StoredDoseEvent] {
            sorted.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == kind }
        }
        return DashboardDerivedDoseMetrics(
            dose1Time: events(.dose1).first?.timestamp,
            dose2Time: events(.dose2).first?.timestamp,
            dose2Skipped: !events(.dose2Skipped).isEmpty,
            extraDoseCount: events(.extraDose).count,
            snoozeCount: events(.snooze).count
        )
    }

    func refreshAndWait() async {
        refresh()
        await refreshTask?.value
    }

    func buildIntegrationStates(healthMatches: Int, whoopMatches: Int = 0) -> [DashboardIntegrationState] {
        let hasReadableHealthData = healthMatches > 0
        let healthState = DashboardIntegrationState(
            id: "healthkit",
            name: "Apple Health",
            status: settings.healthKitEnabled
                ? (healthKit.isAuthorized
                    ? (hasReadableHealthData ? "Data Available" : "Access Requested")
                    : "Access Needed")
                : "Disabled",
            detail: settings.healthKitEnabled
                ? (healthKit.isAuthorized
                    ? (hasReadableHealthData
                        ? "\(healthMatches) nights with Apple Health sleep summaries loaded (up to 120 nights)"
                        : "No readable summaries returned from the last 120 nights. Apple Health intentionally makes denied access and an empty result indistinguishable.")
                    : (healthKit.lastError ?? "Request read access for sleep analysis in Settings"))
                : "Enable in Settings to ingest sleep stages automatically.",
            color: settings.healthKitEnabled
                ? (hasReadableHealthData ? .green : (healthKit.isAuthorized ? .blue : .orange))
                : .gray
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
                        ? "\(whoopMatches) nights loaded (last 30 days)\(syncInfo)"
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
                : "Cloud sync is unavailable in the local-first app target. Your records remain on this device.",
            color: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? .orange : .green)
                : .gray
        )

        return [healthState, whoopState, cloudState]
    }
}
