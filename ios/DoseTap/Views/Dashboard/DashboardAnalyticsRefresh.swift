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
        providerAssociationsReady = false
        doseReviewReadReady = false
        defer { if refreshGeneration == generation { isLoading = false } }
        let asOf = now(), zone = timeZone(), range = selectedRange
        let customRange = customReportingRange
        let access = providerAccess.revision
        refreshProviderAccess = access
        let healthEnabled = providerQueries.healthEnabled()
        let whoopEnabled = providerQueries.whoopEnabled(), whoopConnected = providerQueries.whoopConnected()
        func requestIsCurrent() -> Bool {
            !Task.isCancelled && refreshGeneration == generation && providerAccess.revision == access
                && range == selectedRange && zone == timeZone()
                && customRange == customReportingRange
                && healthEnabled == providerQueries.healthEnabled()
                && whoopEnabled == providerQueries.whoopEnabled() && whoopConnected == providerQueries.whoopConnected()
        }
        let requestedWindow: DashboardReportingWindow
        do { requestedWindow = try resolveReportingWindow(asOf: asOf, timeZone: zone) }
        catch {
            errorMessage = reportingPeriodError(error)
            return
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var refreshErrors: [String] = []
        var health = includeProviders && healthEnabled && healthSnapshot?.matches(timeZone: zone, epoch: access[.health]) == true ? healthSnapshot : nil
        var whoopResult = includeProviders && whoopEnabled && whoopConnected && whoopSnapshot?.matches(timeZone: zone, epoch: access[.whoop]) == true ? whoopSnapshot : nil

        if includeProviders && healthEnabled {
            let preparation = await providerQueries.prepareHealth()
            guard requestIsCurrent() else { return }
            switch preparation {
            case .ready:
                do {
                    let summaries = try await providerQueries.healthHistory(requestedWindow)
                    guard requestIsCurrent() else { return }
                    var values: [String: HealthKitService.SleepNightSummary] = [:]
                    for summary in summaries {
                        let key = sessionKey(for: eveningAnchorDate(for: summary.date, timeZone: zone), timeZone: zone)
                        if values[key] == nil { values[key] = summary }
                    }
                    health = .init(values: values, window: requestedWindow, queryStart: requestedWindow.healthQueryStart, epoch: access[.health])
                } catch {
                    guard requestIsCurrent(), !DashboardProviderFailure.isCancelled(error) else { return }
                    if DashboardProviderFailure.isTransient(error) { health?.failedAttemptAt = asOf } else { health = nil }
                    refreshErrors.append("Apple Health sleep could not refresh. \(health == nil ? "No usable previous results are available." : "Showing a stale snapshot.") Local records remain available.")
                }
            case .transientFailure:
                health?.failedAttemptAt = asOf
                refreshErrors.append("Apple Health access status could not refresh. \(health == nil ? "No usable previous results are available." : "Showing a stale snapshot.")")
            case .unavailable:
                health = nil
                refreshErrors.append("Apple Health access is unavailable. Check access in Settings.")
            }
        }

        if includeProviders && whoopEnabled && whoopConnected {
            do {
                let fetchDays = max(1, min(days, 30))
                let queryEnd = requestedWindow.healthQueryEnd
                let limitStart = calendar.date(byAdding: .day, value: -fetchDays, to: queryEnd) ?? queryEnd
                let startDate = requestedWindow.reviewedPeriod == nil ? limitStart : max(limitStart, requestedWindow.healthQueryStart)
                let result = try await providerQueries.whoopHistory(startDate, queryEnd)
                guard requestIsCurrent() else { return }
                var values: [String: WHOOPNightSummary] = [:]
                for summary in result.summaries {
                    let key = sessionKey(for: summary.date, timeZone: zone)
                    if summary.totalSleepMinutes > (values[key]?.totalSleepMinutes ?? -1) { values[key] = summary }
                }
                whoopResult = .init(values: values, window: requestedWindow, queryStart: startDate,
                                    epoch: access[.whoop], isPartial: result.recoveryStatus == .failed)
                if result.recoveryStatus == .failed { refreshErrors.append("WHOOP sleep refreshed; recovery metrics could not refresh.") }
            } catch {
                guard requestIsCurrent(), !DashboardProviderFailure.isCancelled(error) else { return }
                if DashboardProviderFailure.isTransient(error) { whoopResult?.failedAttemptAt = asOf } else { whoopResult = nil }
                refreshErrors.append("WHOOP sleep could not refresh. \(whoopResult == nil ? "No usable previous results are available." : "Showing a stale snapshot.") Local records remain available.")
            }
        }
        let healthByKey = health?.values ?? [:], whoopByKey = whoopResult?.values ?? [:]

        let aggregates: [DashboardNightAggregate]
        let associations: [DashboardProviderAssociation]
        do {
            let snapshot = try sessionRepo.dashboardIdentitySnapshot()
            associations = snapshot.associations
            let reviews = try sessionRepo.dashboardDoseReviews()
            aggregates = identityAggregates(local: snapshot.sessions, health: healthByKey, whoop: whoopByKey, associations: snapshot.associations)
                .map { row in var row = row; row.doseReviewLedger = reviews[row.id]; return row }
        } catch {
            errorMessage = "Local records could not be read completely. Previous dashboard data is retained. Try Refresh again."
            return
        }

        guard requestIsCurrent() else { return }
        publishedProviderAccess = access
        reportingAsOf = asOf; reportingTimeZone = zone
        reportingPeriod = requestedWindow.reviewedPeriod
        publishedCustomReportingRange = customRange
        healthSnapshot = health; whoopSnapshot = whoopResult
        healthQueryWindow = health?.window
        errorMessage = refreshErrors.isEmpty ? nil : refreshErrors.joined(separator: " ")
        if !refreshErrors.isEmpty { dashboardLogger.warning("Dashboard refresh completed with \(refreshErrors.count, privacy: .public) provider warnings") }
        nights = aggregates
        savedProviderAssociations = associations
        providerAssociationsReady = true
        doseReviewReadReady = true
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
            dose1Time: events(.dose1).count == 1 ? events(.dose1).first?.timestamp : nil,
            dose2Time: events(.dose2).count == 1 ? events(.dose2).first?.timestamp : nil,
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

        func snapshotState<T>(_ state: DashboardIntegrationState, _ snapshot: DashboardProviderSnapshot<T>?) -> DashboardIntegrationState {
            guard let snapshot else { return state }
            let stale = snapshot.failedAttemptAt != nil
            return .init(id: state.id, name: state.name, status: stale ? "Stale" : (snapshot.isPartial ? "Partial" : state.status),
                detail: snapshot.description(provider: state.name), color: stale || snapshot.isPartial ? .orange : state.color)
        }
        return [snapshotState(healthState, healthSnapshot), snapshotState(whoopState, whoopSnapshot), cloudState]
    }
}
