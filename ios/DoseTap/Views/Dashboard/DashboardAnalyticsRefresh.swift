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
        let asOf = now(), zone = timeZone(), range = selectedRange
        guard let requestedWindow = range.window(asOf: asOf, timeZone: zone) else {
            errorMessage = "Reporting dates could not be determined. Check the device date and refresh."
            return
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var refreshError: String?
        var queriedHealth = false

        var healthByKey: [String: HealthKitService.SleepNightSummary] = [:]
        if includeProviders && settings.healthKitEnabled {
            await healthKit.syncAuthorizationState()
            if healthKit.isAuthorized {
                do {
                    queriedHealth = true
                    let summaries = try await healthKit.dashboardSleepHistory(days: requestedWindow.healthQueryDays, through: asOf, calendar: calendar)
                    guard !Task.isCancelled, refreshGeneration == generation else { return }
                    for summary in summaries {
                        let key = sessionKey(for: eveningAnchorDate(for: summary.date, timeZone: zone), timeZone: zone)
                        if healthByKey[key] == nil { healthByKey[key] = summary }
                    }
                } catch {
                    guard !Task.isCancelled, refreshGeneration == generation else { return }
                    refreshError = "Apple Health sleep could not refresh. Local records are still available. Try Refresh again."
                }
            } else if let lastError = healthKit.lastError, !lastError.isEmpty {
                refreshError = lastError
            }
        }

        var whoopByKey: [String: WHOOPNightSummary] = [:]
        if includeProviders && WHOOPService.isEnabled && settings.whoopEnabled && whoop.isConnected {
            do {
                let fetchDays = min(days, 30)
                let endDate = asOf
                let startDate = calendar.date(byAdding: .day, value: -fetchDays, to: endDate) ?? endDate
                let summaries = try await whoop.fetchNightSummaries(from: startDate, to: endDate)
                guard !Task.isCancelled, refreshGeneration == generation else { return }
                if let warning = whoop.lastError { refreshError = warning }
                for summary in summaries {
                    let key = sessionKey(for: summary.date, timeZone: zone)
                    if summary.totalSleepMinutes > (whoopByKey[key]?.totalSleepMinutes ?? -1) {
                        whoopByKey[key] = summary
                    }
                }
            } catch {
                guard !Task.isCancelled, refreshGeneration == generation else { return }
                refreshError = "WHOOP sleep could not refresh. Local records are still available. Try Refresh again."
            }
        }

        let sessionKeys = Set(sessionRepo.allSessionDatesForSync())
            .union(healthByKey.keys).union(whoopByKey.keys).sorted(by: >)
        var aggregates: [DashboardNightAggregate] = []
        for key in sessionKeys {
            guard !Task.isCancelled, refreshGeneration == generation else { return }
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

        guard !Task.isCancelled, refreshGeneration == generation,
              range == selectedRange, zone == timeZone() else { return }
        reportingAsOf = asOf; reportingTimeZone = zone
        healthQueryWindow = queriedHealth ? requestedWindow : nil
        errorMessage = refreshError
        nights = aggregates.sorted { $0.sessionDate > $1.sessionDate }
        integrationStates = buildIntegrationStates(healthMatches: healthByKey.count, whoopMatches: whoopByKey.count)
        lastRefresh = asOf
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
                        ? "\(healthMatches) nights with Apple Health sleep summaries loaded (up to \(healthQueryWindow?.healthQueryDays ?? 0) days)"
                        : "No readable summaries returned from the last \(healthQueryWindow?.healthQueryDays ?? 0) days. Apple Health intentionally makes denied access and an empty result indistinguishable.")
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
