import Foundation
import SwiftUI

// MARK: - Health Data Card

struct AppleHealthNightSummaryData {
    let totalSleepMinutes: Double
    let ttfwMinutes: Double?
    let wakeCount: Int
    let sleepOnset: Date?
    let finalWake: Date?
    let averageHeartRate: Double?
    let respiratoryRate: Double?
    let hrvMs: Double?
    let restingHeartRate: Double?
    let sources: [String]
}

struct HealthDataSnapshotModel {
    let appleSummary: AppleHealthNightSummaryData?
    let appleStatus: String
    let whoopSummary: WHOOPNightSummary?
    let whoopStatus: String
}

@MainActor
enum HealthDataSnapshotLoader {
    static func load(
        sessionKey: String
    ) async -> HealthDataSnapshotModel {
        await load(
            sessionKey: sessionKey,
            healthKit: HealthKitService.shared,
            settings: UserSettingsManager.shared,
            whoop: WHOOPService.shared
        )
    }

    static func load(
        sessionKey: String,
        healthKit: HealthKitService,
        settings: UserSettingsManager,
        whoop: WHOOPService
    ) async -> HealthDataSnapshotModel {
        let apple = await loadAppleHealthSummary(sessionKey: sessionKey, healthKit: healthKit, settings: settings)
        let whoopSummary = await loadWhoopSummary(sessionKey: sessionKey, settings: settings, whoop: whoop)
        return HealthDataSnapshotModel(
            appleSummary: apple.summary,
            appleStatus: apple.status,
            whoopSummary: whoopSummary.summary,
            whoopStatus: whoopSummary.status
        )
    }

    private static func loadAppleHealthSummary(
        sessionKey: String,
        healthKit: HealthKitService,
        settings: UserSettingsManager
    ) async -> (summary: AppleHealthNightSummaryData?, status: String) {
        guard healthKit.isAvailable else {
            return (nil, "Unavailable on this device")
        }

        guard settings.healthKitEnabled else {
            return (nil, "Disabled in Settings")
        }

        healthKit.checkAuthorizationStatus()
        guard healthKit.isAuthorized else {
            return (nil, "Not authorized")
        }

        guard let queryRange = queryRange(for: sessionKey) else {
            return (nil, "Invalid session date")
        }

        do {
            let segments = try await healthKit.fetchSegmentsForTimeline(from: queryRange.start, to: queryRange.end)
            let biometrics = try await healthKit.fetchNightBiometrics(from: queryRange.start, to: queryRange.end)
            guard !segments.isEmpty else {
                if biometrics.hasAnyMetric {
                    return (
                        AppleHealthNightSummaryData(
                            totalSleepMinutes: 0,
                            ttfwMinutes: nil,
                            wakeCount: 0,
                            sleepOnset: nil,
                            finalWake: nil,
                            averageHeartRate: biometrics.averageHeartRate,
                            respiratoryRate: biometrics.respiratoryRate,
                            hrvMs: biometrics.hrvMs,
                            restingHeartRate: biometrics.restingHeartRate,
                            sources: []
                        ),
                        "Connected"
                    )
                }
                return (nil, "No Apple Health data for this night")
            }

            let sorted = segments.sorted { $0.start < $1.start }
            let sleepOnset = sorted.first { $0.stage.isAsleep }?.start
            let finalWake = sorted.last?.end

            var firstWake: Date?
            var foundSleep = false
            for segment in sorted {
                if segment.stage.isAsleep {
                    foundSleep = true
                } else if foundSleep && segment.stage == .awake {
                    firstWake = segment.start
                    break
                }
            }

            let totalSleepMinutes = sorted
                .filter { $0.stage.isAsleep }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
            let wakeCount = sorted.filter { $0.stage == .awake }.count
            let ttfwMinutes = (sleepOnset != nil && firstWake != nil)
                ? firstWake!.timeIntervalSince(sleepOnset!) / 60
                : nil
            let sources = Array(Set(sorted.map(\.source))).sorted()

            return (
                AppleHealthNightSummaryData(
                    totalSleepMinutes: totalSleepMinutes,
                    ttfwMinutes: ttfwMinutes,
                    wakeCount: wakeCount,
                    sleepOnset: sleepOnset,
                    finalWake: finalWake,
                    averageHeartRate: biometrics.averageHeartRate,
                    respiratoryRate: biometrics.respiratoryRate,
                    hrvMs: biometrics.hrvMs,
                    restingHeartRate: biometrics.restingHeartRate,
                    sources: sources
                ),
                "Connected"
            )
        } catch {
            return (nil, "Apple Health error: \(error.localizedDescription)")
        }
    }

    private static func loadWhoopSummary(
        sessionKey: String,
        settings: UserSettingsManager,
        whoop: WHOOPService
    ) async -> (summary: WHOOPNightSummary?, status: String) {
        guard WHOOPService.isEnabled, settings.whoopEnabled else {
            return (nil, "Disabled in Settings")
        }

        guard whoop.isConnected else {
            return (nil, "Not connected")
        }

        guard let queryRange = queryRange(for: sessionKey) else {
            return (nil, "Invalid session date")
        }

        do {
            let sleeps = try await whoop.fetchSleepData(from: queryRange.start, to: queryRange.end)
            var summariesByKey: [String: WHOOPNightSummary] = [:]
            var pendingSleepCount = 0
            for sleep in sleeps {
                if let state = sleep.scoreState?.uppercased(), state != "SCORED" {
                    pendingSleepCount += 1
                }
                let summary = sleep.toNightSummary()
                guard summary.hasValidSleepData else { continue }
                let mappedKey = SessionRepository.shared.sessionDateString(for: summary.date)
                if summariesByKey[mappedKey] == nil {
                    summariesByKey[mappedKey] = summary
                }
            }

            do {
                let recoveries = try await whoop.fetchRecoveryData(from: queryRange.start, to: queryRange.end)
                for recovery in recoveries {
                    guard let sleepId = recovery.sleepId,
                          let matchedKey = summariesByKey.first(where: { $0.value.sleepId == sleepId })?.key,
                          var summary = summariesByKey[matchedKey] else {
                        continue
                    }
                    summary.recoveryScore = recovery.score?.recoveryScore
                    summary.hrvMs = recovery.score?.hrvMs
                    summary.restingHeartRate = recovery.score?.restingHeartRate
                    summariesByKey[matchedKey] = summary
                }
            } catch {
                // Recovery is additive; keep sleep data visible even when recovery enrichment fails.
            }

            if let matched = summariesByKey[sessionKey] {
                return (matched, "Connected")
            }

            if !sleeps.isEmpty, summariesByKey.isEmpty {
                if pendingSleepCount > 0 {
                    return (nil, "WHOOP sleep was found but not scored yet")
                }
                return (nil, "WHOOP returned sleep records, but none had usable stage data")
            }

            if !summariesByKey.isEmpty {
                let matchedKeys = summariesByKey.keys.sorted().joined(separator: ", ")
                return (nil, "WHOOP sleep matched other session dates: \(matchedKeys)")
            }

            return (nil, "No WHOOP sleep data for this night")
        } catch {
            return (nil, "WHOOP error: \(error.localizedDescription)")
        }
    }

    private static func queryRange(for sessionKey: String) -> (start: Date, end: Date)? {
        guard let nightDate = AppFormatters.sessionDate.date(from: sessionKey),
              let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else {
            return nil
        }

        return (
            start: eveningAnchorDate(for: nightDate, hour: 18),
            end: eveningAnchorDate(for: nextDay, hour: 12)
        )
    }
}

struct HealthDataCard: View {
    let sessionKey: String
    @State private var snapshot = HealthDataSnapshotModel(
        appleSummary: nil,
        appleStatus: "Loading Apple Health...",
        whoopSummary: nil,
        whoopStatus: "Loading WHOOP..."
    )
    @State private var isLoading = false

    var body: some View {
        HealthDataCardContent(snapshot: snapshot, isLoading: isLoading)
            .task(id: sessionKey) {
                await loadHealthData()
            }
    }

    private func loadHealthData() async {
        isLoading = true
        defer { isLoading = false }
        snapshot = await HealthDataSnapshotLoader.load(sessionKey: sessionKey)
    }
}

struct HealthDataSnapshotCard: View {
    let snapshot: HealthDataSnapshotModel

    var body: some View {
        HealthDataCardContent(snapshot: snapshot, isLoading: false)
    }
}

private struct HealthDataCardContent: View {
    let snapshot: HealthDataSnapshotModel
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 Health Integrations")
                .font(.headline)

            VStack(spacing: 12) {
                appleHealthSection
                Divider()
                whoopSection
            }

            Text("Apple Health sleep stages and biometrics are matched beside WHOOP sleep and recovery for this session date.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    @ViewBuilder
    private var appleHealthSection: some View {
        if let summary = snapshot.appleSummary {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("Apple Health")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack(spacing: 16) {
                    if summary.totalSleepMinutes > 0 {
                        healthMetric(value: formatSleepMinutes(summary.totalSleepMinutes), label: "Sleep")
                    }
                    if let ttfw = summary.ttfwMinutes {
                        healthMetric(value: "\(Int(ttfw.rounded())) min", label: "TTFW")
                    }
                    if summary.wakeCount > 0 || summary.totalSleepMinutes > 0 {
                        healthMetric(value: "\(summary.wakeCount)", label: "Wakes")
                    }
                    if let heartRate = summary.averageHeartRate {
                        healthMetric(value: String(format: "%.0f", heartRate), label: "HR bpm")
                    }
                }

                HStack(spacing: 16) {
                    if let onset = summary.sleepOnset {
                        healthMetric(value: AppFormatters.shortTime.string(from: onset), label: "Asleep")
                    }
                    if let finalWake = summary.finalWake {
                        healthMetric(value: AppFormatters.shortTime.string(from: finalWake), label: "Wake")
                    }
                    if let rr = summary.respiratoryRate {
                        healthMetric(value: String(format: "%.1f", rr), label: "RR brpm")
                    }
                    if let hrv = summary.hrvMs {
                        healthMetric(value: String(format: "%.0f", hrv), label: "HRV ms")
                    }
                    if let restingHeartRate = summary.restingHeartRate {
                        healthMetric(value: String(format: "%.0f", restingHeartRate), label: "RHR")
                    }
                }

                if !summary.sources.isEmpty {
                    Text("Sources: \(summary.sources.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if isLoading {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Apple Health data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HealthIntegrationRow(
                source: "Apple Health",
                icon: "heart.fill",
                iconColor: .red,
                data: [("Status", snapshot.appleStatus)]
            )
        }
    }

    @ViewBuilder
    private var whoopSection: some View {
        if let summary = snapshot.whoopSummary, summary.hasValidSleepData {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.green)
                    Text("WHOOP")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack(spacing: 16) {
                    healthMetric(value: summary.formattedTotalSleep, label: "Sleep")
                    if let recovery = summary.recoveryScore {
                        healthMetric(value: String(format: "%.0f%%", recovery), label: "Recovery")
                    }
                    if let hrv = summary.hrvMs {
                        healthMetric(value: String(format: "%.0f", hrv), label: "HRV ms")
                    }
                    if let efficiency = summary.sleepEfficiency {
                        healthMetric(value: String(format: "%.0f%%", efficiency), label: "Efficiency")
                    }
                }

                HStack(spacing: 16) {
                    if let rr = summary.respiratoryRate {
                        healthMetric(value: String(format: "%.1f", rr), label: "RR brpm")
                    }
                    if let restingHeartRate = summary.restingHeartRate {
                        healthMetric(value: String(format: "%.0f", restingHeartRate), label: "RHR")
                    }
                    if summary.disturbanceCount > 0 {
                        healthMetric(value: "\(summary.disturbanceCount)", label: "Disturbances")
                    }
                    healthMetric(value: "\(summary.deepMinutes)m", label: "Deep")
                    healthMetric(value: "\(summary.remMinutes)m", label: "REM")
                }

                if let lastSync = WHOOPService.shared.lastSyncTime {
                    Text("Last sync \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if isLoading {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading WHOOP data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HealthIntegrationRow(
                source: "WHOOP",
                icon: "waveform.path.ecg",
                iconColor: WHOOPService.shared.isConnected ? .green : .gray,
                data: [("Status", snapshot.whoopStatus)]
            )
        }
    }

    private func healthMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func formatSleepMinutes(_ totalMinutes: Double) -> String {
        let rounded = Int(totalMinutes.rounded())
        let hours = rounded / 60
        let minutes = rounded % 60
        return "\(hours)h \(minutes)m"
    }
}

struct HealthIntegrationRow: View {
    let source: String
    let icon: String
    let iconColor: Color
    let data: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(source)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack(spacing: 16) {
                ForEach(data, id: \.0) { item in
                    VStack(spacing: 2) {
                        Text(item.1)
                            .font(.headline)
                        Text(item.0)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
