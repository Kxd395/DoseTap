import SwiftUI

// Extracted from SettingsView.swift — HealthKit integration settings

// MARK: - HealthKit Settings View
struct HealthKitSettingsView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @State private var isLoading = false
    @State private var showingBaseline = false
    private let defaultProvider: any HealthKitProviding = HealthKitProviderFactory.makeDefault()
    
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
                        Label("Status", systemImage: "heart.fill")
                        Spacer()
                        if healthKit.isAuthorized {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .labelStyle(.titleOnly)
                        } else {
                            Text("Not Connected")
                                .foregroundColor(.secondary)
                        }
                    }
                    
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
                                Label("Connect Apple Health", systemImage: "link")
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    } else {
                        Toggle(isOn: $settings.healthKitEnabled) {
                            Label("Use Sleep Data", systemImage: "bed.double.fill")
                        }
                    }
                } header: {
                    Label("Apple Health", systemImage: "heart.text.square")
                } footer: {
                    Text("DoseTap reads sleep data to learn your patterns and optimize wake times.")
                }
                
                if healthKit.isAuthorized && settings.healthKitEnabled {
                    Section {
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
                            Label("Recent Nights", systemImage: "calendar")
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
