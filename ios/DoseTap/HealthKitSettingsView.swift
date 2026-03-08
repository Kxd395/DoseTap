import SwiftUI

// Extracted from SettingsView.swift — HealthKit integration settings

// MARK: - HealthKit Settings View
struct HealthKitSettingsView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @State private var isLoading = false
    @State private var showingBaseline = false
    private let defaultProvider: any HealthKitProviding = HealthKitProviderFactory.makeDefault()

    private var connectionTitle: String {
        if !healthKit.isAvailable {
            return "Unavailable"
        }
        if healthKit.isAuthorized && settings.healthKitEnabled {
            return "Connected"
        }
        if healthKit.isAuthorized {
            return "Connected"
        }
        return "Not Connected"
    }

    private var connectionSubtitle: String {
        if !healthKit.isAvailable {
            return "Apple Health is unavailable on this device"
        }
        if healthKit.isAuthorized && settings.healthKitEnabled {
            return "Sleep access is enabled in DoseTap"
        }
        if healthKit.isAuthorized {
            return "Permission granted, but disabled in DoseTap"
        }
        return "Grant sleep access to sync Apple Health nights"
    }
    
    var body: some View {
        List {
            if defaultProvider is NoOpHealthKitProvider {
                Section {
                    Label("Apple Health is unavailable (simulator or missing entitlements)", systemImage: "heart.slash")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("On simulator and unsigned builds, Apple Health is unavailable. The app defaults to a no-op provider for safety.")
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: healthKit.isAuthorized ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(healthKit.isAuthorized ? .green : .secondary)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionTitle)
                                .font(.headline)
                            Text(connectionSubtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if healthKit.isAuthorized {
                        Toggle(isOn: $settings.healthKitEnabled) {
                            Label("Use Sleep Data", systemImage: "bed.double.fill")
                        }
                    }
                } header: {
                    Label("Connection", systemImage: "link")
                }

                Section {
                    if !healthKit.isAuthorized {
                        Button {
                            Task {
                                isLoading = true
                                settings.healthKitEnabled = true
                                let authorized = await healthKit.requestAuthorization()
                                isLoading = false
                                if !authorized {
                                    healthKit.checkAuthorizationStatus()
                                }
                            }
                        } label: {
                            HStack {
                                Label("Connect Apple Health", systemImage: "link.badge.plus")
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    }

                    if healthKit.isAuthorized && settings.healthKitEnabled {
                        Button {
                            Task {
                                isLoading = true
                                await healthKit.computeTTFWBaseline(days: 14)
                                isLoading = false
                                showingBaseline = true
                            }
                        } label: {
                            HStack {
                                Label("Compute Sleep Baseline", systemImage: "chart.line.uptrend.xyaxis")
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    }
                } header: {
                    Label("Actions", systemImage: "hand.tap")
                }

                if healthKit.isAuthorized && settings.healthKitEnabled {
                    Section {
                        if let baseline = healthKit.ttfwBaseline {
                            HStack {
                                Label("Avg Time to First Wake", systemImage: "clock.fill")
                                Spacer()
                                Text("\(Int(baseline)) min")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }

                            if let nudge = healthKit.calculateNudgeSuggestion() {
                                HStack {
                                    Label("Suggested Nudge", systemImage: "arrow.left.arrow.right")
                                    Spacer()
                                    Text(nudge >= 0 ? "+\(nudge) min" : "\(nudge) min")
                                        .foregroundColor(nudge >= 0 ? .green : .orange)
                                        .fontWeight(.semibold)
                                }
                            }
                        } else {
                            Text("Run sleep baseline once to calculate your average time to first wake.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Label("Sleep Analysis", systemImage: "waveform.path.ecg")
                    } footer: {
                        Text("Analyzes 14 nights of sleep data to find your natural wake rhythm.")
                    }

                    if !healthKit.sleepHistory.isEmpty {
                        Section {
                            ForEach(healthKit.sleepHistory.prefix(7)) { night in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(night.date, style: .date)
                                            .font(.subheadline)
                                        Text("\(Int(night.totalSleepMinutes / 60))h \(Int(night.totalSleepMinutes.truncatingRemainder(dividingBy: 60)))m sleep")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let ttfw = night.ttfwMinutes {
                                        VStack(alignment: .trailing) {
                                            Text("\(Int(ttfw)) min")
                                                .font(.subheadline.bold())
                                            Text("TTFW")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text("No data")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Label("Recent Sleep", systemImage: "moon.zzz.fill")
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("What We Read")
                                .font(.subheadline.bold())
                        }
                        Text("• Sleep analysis (bed time, sleep stages, wake times)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Used to calculate TTFW (Time to First Wake)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Data stays on your device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if let error = healthKit.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Apple Health")
        .onAppear {
            healthKit.checkAuthorizationStatus()
        }
    }
}

// MARK: - Compact Apple Health Status for Settings List

struct AppleHealthStatusRow: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared

    private var statusText: String {
        if !healthKit.isAvailable {
            return "Unavailable on this device"
        }
        if healthKit.isAuthorized && settings.healthKitEnabled {
            return "Connected"
        }
        if healthKit.isAuthorized {
            return "Connected, but disabled in DoseTap"
        }
        return "Not connected"
    }

    private var statusColor: Color {
        if healthKit.isAuthorized && settings.healthKitEnabled {
            return .green
        }
        if healthKit.isAuthorized {
            return .orange
        }
        return .secondary
    }

    var body: some View {
        NavigationLink {
            HealthKitSettingsView()
        } label: {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.teal)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                        .font(.body)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }

                Spacer()

                if healthKit.isAuthorized && settings.healthKitEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .onAppear {
            healthKit.checkAuthorizationStatus()
        }
    }
}
