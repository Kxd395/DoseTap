import SwiftUI
import HealthKit

/// Test view to verify HealthKit + WHOOP data access
struct HealthKitTestView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    
    @State private var overnightData: HealthKitManager.OvernightSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            List {
                // Authorization Section
                Section("Authorization") {
                    HStack {
                        Text("HealthKit Access")
                        Spacer()
                        if healthKit.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Request Access") {
                                Task { await requestAccess() }
                            }
                        }
                    }
                }
                
                // Summary Section
                if let data = overnightData {
                    Section("Overnight HR Summary") {
                        HStack {
                            Text("Samples")
                            Spacer()
                            Text("\(data.heartRateSamples.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        if let min = data.minHR {
                            HStack {
                                Text("Min HR")
                                Spacer()
                                Text("\(Int(min)) bpm")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if let avg = data.avgHR {
                            HStack {
                                Text("Avg HR")
                                Spacer()
                                Text("\(Int(avg)) bpm")
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if let max = data.maxHR {
                            HStack {
                                Text("Max HR")
                                Spacer()
                                Text("\(Int(max)) bpm")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    // WHOOP-specific
                    Section("WHOOP Data") {
                        let whoopSamples = data.whoopHeartRateSamples
                        HStack {
                            Text("WHOOP Samples")
                            Spacer()
                            Text("\(whoopSamples.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        if whoopSamples.isEmpty {
                            Text("No WHOOP data found. Make sure WHOOP → Health is enabled.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // HRV
                    Section("HRV") {
                        HStack {
                            Text("Samples")
                            Spacer()
                            Text("\(data.hrvSamples.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        if let avgHRV = data.avgHRV {
                            HStack {
                                Text("Avg HRV (SDNN)")
                                Spacer()
                                Text("\(Int(avgHRV)) ms")
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    
                    // Sleep Segments
                    Section("Sleep Stages") {
                        if data.sleepSegments.isEmpty {
                            Text("No sleep data found")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(data.sleepSegments) { segment in
                                HStack {
                                    Text(segment.stage.rawValue)
                                    Spacer()
                                    Text(formatTimeRange(segment.start, segment.end))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Data Sources
                    Section("Data Sources") {
                        let sources = Set(data.heartRateSamples.map(\.source))
                        ForEach(Array(sources), id: \.self) { source in
                            Text(source)
                        }
                    }
                }
                
                // Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("HealthKit Test")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await fetchData() } }) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading || !healthKit.isAuthorized)
                }
            }
        }
    }
    
    private func requestAccess() async {
        do {
            try await healthKit.requestAuthorization()
            await fetchData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func fetchData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            overnightData = try await healthKit.fetchOvernightSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func formatTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

#Preview {
    HealthKitTestView()
}
