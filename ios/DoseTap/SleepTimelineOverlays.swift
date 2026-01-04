import SwiftUI

// MARK: - Biometric Data Models

/// Heart rate data point for timeline overlay
struct HeartRateDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let bpm: Double
}

/// Respiratory rate data point for timeline overlay
struct RespiratoryRateDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let breathsPerMinute: Double
}

/// HRV data point for timeline overlay
struct HRVDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rmssd: Double // Root mean square of successive differences
}

// MARK: - Biometric Timeline Overlay

/// Overlay component showing HR, RR, or HRV on sleep timeline
struct BiometricOverlay: View {
    let dataType: BiometricDataType
    let dataPoints: [any BiometricDataPointProtocol]
    let startTime: Date
    let endTime: Date
    let geometryWidth: CGFloat
    let overlayHeight: CGFloat
    
    enum BiometricDataType {
        case heartRate
        case respiratoryRate
        case hrv
        
        var color: Color {
            switch self {
            case .heartRate: return .red
            case .respiratoryRate: return .cyan
            case .hrv: return .green
            }
        }
        
        var icon: String {
            switch self {
            case .heartRate: return "heart.fill"
            case .respiratoryRate: return "lungs.fill"
            case .hrv: return "waveform.path.ecg"
            }
        }
        
        var label: String {
            switch self {
            case .heartRate: return "HR"
            case .respiratoryRate: return "RR"
            case .hrv: return "HRV"
            }
        }
        
        var unit: String {
            switch self {
            case .heartRate: return "bpm"
            case .respiratoryRate: return "brpm"
            case .hrv: return "ms"
            }
        }
    }
    
    private var normalizedValues: [(x: CGFloat, y: CGFloat, value: Double)] {
        guard !dataPoints.isEmpty else { return [] }
        
        let totalDuration = endTime.timeIntervalSince(startTime)
        let values = dataPoints.map { $0.value }
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range = max(maxVal - minVal, 1) // Prevent division by zero
        
        return dataPoints.map { point in
            let xOffset = point.timestamp.timeIntervalSince(startTime)
            let x = CGFloat(xOffset / totalDuration) * geometryWidth
            let normalizedY = (point.value - minVal) / range
            let y = overlayHeight - (CGFloat(normalizedY) * (overlayHeight - 8)) - 4 // Invert and add padding
            return (x: x, y: y, value: point.value)
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Line connecting points
            Path { path in
                let points = normalizedValues
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x, y: first.y))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x, y: point.y))
                }
            }
            .stroke(dataType.color, lineWidth: 1.5)
            
            // Data points
            ForEach(Array(normalizedValues.enumerated()), id: \.offset) { index, point in
                Circle()
                    .fill(dataType.color)
                    .frame(width: 4, height: 4)
                    .position(x: point.x, y: point.y)
            }
        }
        .frame(height: overlayHeight)
    }
}

// MARK: - Protocol for Generic Data Points

protocol BiometricDataPointProtocol {
    var timestamp: Date { get }
    var value: Double { get }
}

extension HeartRateDataPoint: BiometricDataPointProtocol {
    var value: Double { bpm }
}

extension RespiratoryRateDataPoint: BiometricDataPointProtocol {
    var value: Double { breathsPerMinute }
}

extension HRVDataPoint: BiometricDataPointProtocol {
    var value: Double { rmssd }
}

// MARK: - Enhanced Sleep Timeline with Overlays

struct EnhancedSleepTimeline: View {
    let stages: [SleepStageBand]
    let events: [TimelineEvent]
    let startTime: Date
    let endTime: Date
    
    // Optional biometric overlays
    var heartRateData: [HeartRateDataPoint] = []
    var respiratoryRateData: [RespiratoryRateDataPoint] = []
    var hrvData: [HRVDataPoint] = []
    
    @State private var showHeartRate = true
    @State private var showRespiratoryRate = true
    @State private var showHRV = false
    
    private let stageColors: [SleepStage: Color] = [
        .awake: .red.opacity(0.7),
        .light: .blue.opacity(0.4),
        .core: .blue.opacity(0.6),
        .deep: .indigo.opacity(0.8),
        .rem: .purple.opacity(0.7)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Sleep Timeline")
                    .font(.headline)
                Spacer()
                Text("\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Stage bands with optional overlays
            GeometryReader { geo in
                let totalDuration = endTime.timeIntervalSince(startTime)
                
                ZStack(alignment: .topLeading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    
                    // Stage bands (bottom half)
                    ForEach(stages) { stage in
                        let startOffset = stage.startTime.timeIntervalSince(startTime)
                        let duration = stage.endTime.timeIntervalSince(stage.startTime)
                        let xPos = (startOffset / totalDuration) * geo.size.width
                        let width = (duration / totalDuration) * geo.size.width
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stageColors[stage.stage] ?? .gray)
                            .frame(width: max(2, width), height: 32)
                            .offset(x: xPos, y: geo.size.height - 36)
                    }
                    
                    // HR overlay
                    if showHeartRate && !heartRateData.isEmpty {
                        BiometricOverlay(
                            dataType: .heartRate,
                            dataPoints: heartRateData,
                            startTime: startTime,
                            endTime: endTime,
                            geometryWidth: geo.size.width,
                            overlayHeight: 40
                        )
                        .offset(y: 4)
                    }
                    
                    // RR overlay
                    if showRespiratoryRate && !respiratoryRateData.isEmpty {
                        BiometricOverlay(
                            dataType: .respiratoryRate,
                            dataPoints: respiratoryRateData,
                            startTime: startTime,
                            endTime: endTime,
                            geometryWidth: geo.size.width,
                            overlayHeight: 40
                        )
                        .offset(y: 44)
                    }
                    
                    // Event markers
                    ForEach(events) { event in
                        let offset = event.time.timeIntervalSince(startTime)
                        let xPos = (offset / totalDuration) * geo.size.width
                        
                        VStack(spacing: 2) {
                            Image(systemName: event.icon)
                                .font(.system(size: 8))
                                .foregroundColor(event.color)
                            Rectangle()
                                .fill(event.color.opacity(0.5))
                                .frame(width: 1, height: geo.size.height - 20)
                        }
                        .offset(x: xPos - 4)
                    }
                }
            }
            .frame(height: hasOverlays ? 120 : 48)
            
            // Legend with overlay toggles
            VStack(spacing: 8) {
                // Stage legend
                HStack(spacing: 12) {
                    StageLegendItem(stage: .awake, color: stageColors[.awake]!)
                    StageLegendItem(stage: .light, color: stageColors[.light]!)
                    StageLegendItem(stage: .deep, color: stageColors[.deep]!)
                    StageLegendItem(stage: .rem, color: stageColors[.rem]!)
                }
                .font(.caption2)
                
                // Biometric toggles (when data available)
                if hasAnyBiometricData {
                    Divider()
                    
                    HStack(spacing: 16) {
                        if !heartRateData.isEmpty {
                            BiometricToggle(
                                type: .heartRate,
                                isOn: $showHeartRate,
                                latestValue: heartRateData.last?.bpm
                            )
                        }
                        
                        if !respiratoryRateData.isEmpty {
                            BiometricToggle(
                                type: .respiratoryRate,
                                isOn: $showRespiratoryRate,
                                latestValue: respiratoryRateData.last?.breathsPerMinute
                            )
                        }
                        
                        if !hrvData.isEmpty {
                            BiometricToggle(
                                type: .hrv,
                                isOn: $showHRV,
                                latestValue: hrvData.last?.rmssd
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var hasAnyBiometricData: Bool {
        !heartRateData.isEmpty || !respiratoryRateData.isEmpty || !hrvData.isEmpty
    }
    
    private var hasOverlays: Bool {
        (showHeartRate && !heartRateData.isEmpty) ||
        (showRespiratoryRate && !respiratoryRateData.isEmpty) ||
        (showHRV && !hrvData.isEmpty)
    }
}

// MARK: - Biometric Toggle

struct BiometricToggle: View {
    let type: BiometricOverlay.BiometricDataType
    @Binding var isOn: Bool
    let latestValue: Double?
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.system(size: 10))
                    .foregroundColor(isOn ? type.color : .secondary)
                
                Text(type.label)
                    .font(.caption2)
                    .foregroundColor(isOn ? .primary : .secondary)
                
                if let value = latestValue {
                    Text(formattedValue(value))
                        .font(.caption2.bold())
                        .foregroundColor(isOn ? type.color : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? type.color.opacity(0.15) : Color(.systemGray5))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formattedValue(_ value: Double) -> String {
        switch type {
        case .heartRate:
            return "\(Int(value))"
        case .respiratoryRate:
            return String(format: "%.1f", value)
        case .hrv:
            return "\(Int(value))"
        }
    }
}

// MARK: - WHOOP Data Integration

extension WHOOPService {
    /// Convert WHOOP sleep record to biometric data points
    func extractBiometricData(from sleep: WHOOPSleepRecord) -> (
        heartRate: [HeartRateDataPoint],
        respiratoryRate: [RespiratoryRateDataPoint],
        hrv: [HRVDataPoint]
    ) {
        // For now, create sample data from the sleep record
        // In a real implementation, this would come from the WHOOP sleep stages endpoint
        var hrPoints: [HeartRateDataPoint] = []
        var rrPoints: [RespiratoryRateDataPoint] = []
        var hrvPoints: [HRVDataPoint] = []
        
        guard let startTime = sleep.start, let endTime = sleep.end else {
            return (hrPoints, rrPoints, hrvPoints)
        }
        let totalDuration = endTime.timeIntervalSince(startTime)
        guard totalDuration > 0 else {
            return (hrPoints, rrPoints, hrvPoints)
        }
        
        // Generate sample points (every 10 minutes)
        let interval: TimeInterval = 600 // 10 minutes
        var currentTime = startTime
        
        // Base values from WHOOP data
        let baseRR = sleep.score?.respiratoryRate ?? 15.0
        
        while currentTime < endTime {
            // Heart rate varies with sleep stage
            let progress = currentTime.timeIntervalSince(startTime) / totalDuration
            let baseHR = 55 + sin(progress * .pi * 4) * 10 // Simulated variation
            hrPoints.append(HeartRateDataPoint(timestamp: currentTime, bpm: baseHR))
            
            // Respiratory rate stays relatively stable
            let rrVariation = (Double.random(in: -0.5...0.5))
            rrPoints.append(RespiratoryRateDataPoint(timestamp: currentTime, breathsPerMinute: baseRR + rrVariation))
            
            // HRV varies inversely with HR
            let baseHRV = 40 - sin(progress * .pi * 4) * 15
            hrvPoints.append(HRVDataPoint(timestamp: currentTime, rmssd: max(20, baseHRV)))
            
            currentTime = currentTime.addingTimeInterval(interval)
        }
        
        return (hrPoints, rrPoints, hrvPoints)
    }
}

// MARK: - Live Enhanced Timeline View

struct LiveEnhancedTimelineView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var whoop = WHOOPService.shared
    
    @State private var stages: [SleepStageBand] = []
    @State private var events: [TimelineEvent] = []
    @State private var heartRateData: [HeartRateDataPoint] = []
    @State private var respiratoryRateData: [RespiratoryRateDataPoint] = []
    @State private var hrvData: [HRVDataPoint] = []
    @State private var isLoading = true
    @State private var selectedDate: Date = Date()
    
    var body: some View {
        VStack {
            // Date picker
            DatePicker("Night of", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .padding(.horizontal)
            
            if isLoading {
                ProgressView("Loading sleep data...")
                    .padding()
            } else if stages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No sleep data for this night")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        EnhancedSleepTimeline(
                            stages: stages,
                            events: events,
                            startTime: nightStart,
                            endTime: nightEnd,
                            heartRateData: heartRateData,
                            respiratoryRateData: respiratoryRateData,
                            hrvData: hrvData
                        )
                        
                        // Source indicator
                        HStack {
                            Image(systemName: whoop.isConnected ? "w.circle.fill" : "heart.fill")
                                .foregroundColor(whoop.isConnected ? .black : .red)
                            Text(whoop.isConnected ? "WHOOP + HealthKit" : "HealthKit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Sleep Timeline")
        .onChange(of: selectedDate) { _ in
            Task { await loadData() }
        }
        .task {
            await loadData()
        }
    }
    
    private var nightStart: Date {
        stages.first?.startTime ?? Calendar.current.date(byAdding: .hour, value: -8, to: Date())!
    }
    
    private var nightEnd: Date {
        stages.last?.endTime ?? Date()
    }
    
    /// Map HealthKit sleep stage to timeline sleep stage
    private func mapHealthKitStage(_ hkStage: HealthKitService.SleepStage) -> SleepStage? {
        switch hkStage {
        case .awake:
            return .awake
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .asleepREM:
            return .rem
        case .asleep:
            return .light
        case .inBed:
            return nil // Filter out "in bed" segments
        }
    }
    
    private func loadData() async {
        isLoading = true
        
        // Load HealthKit sleep stages
        do {
            let (start, end) = nightRange(for: selectedDate)
            let segments = try await healthKit.fetchSegmentsForTimeline(from: start, to: end)
            // Convert SleepSegment to SleepStageBand
            stages = segments.compactMap { segment in
                guard let mappedStage = mapHealthKitStage(segment.stage) else { return nil }
                return SleepStageBand(
                    stage: mappedStage,
                    startTime: segment.start,
                    endTime: segment.end
                )
            }
        } catch {
            stages = []
        }
        
        // Load WHOOP biometric data if connected
        if whoop.isConnected {
            do {
                let sleepRecords = try await whoop.fetchRecentSleep(nights: 1)
                if let record = sleepRecords.first {
                    let biometrics = whoop.extractBiometricData(from: record)
                    heartRateData = biometrics.heartRate
                    respiratoryRateData = biometrics.respiratoryRate
                    hrvData = biometrics.hrv
                }
            } catch {
                // WHOOP data optional - don't show error
                heartRateData = []
                respiratoryRateData = []
                hrvData = []
            }
        }
        
        isLoading = false
    }
    
    private func nightRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        // Night starts at 8 PM previous day
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 20
        components.minute = 0
        let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
        var startComponents = calendar.dateComponents([.year, .month, .day], from: previousDay)
        startComponents.hour = 20
        let start = calendar.date(from: startComponents) ?? date
        
        // Night ends at 12 PM
        components.hour = 12
        let end = calendar.date(from: components) ?? date
        
        return (start, end)
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancedSleepTimeline_Previews: PreviewProvider {
    static var previews: some View {
        let now = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -8, to: now)!
        
        // Sample stages
        let stages = [
            SleepStageBand(stage: .awake, startTime: startTime, endTime: startTime.addingTimeInterval(600)),
            SleepStageBand(stage: .light, startTime: startTime.addingTimeInterval(600), endTime: startTime.addingTimeInterval(3600)),
            SleepStageBand(stage: .deep, startTime: startTime.addingTimeInterval(3600), endTime: startTime.addingTimeInterval(7200)),
            SleepStageBand(stage: .rem, startTime: startTime.addingTimeInterval(7200), endTime: startTime.addingTimeInterval(10800)),
            SleepStageBand(stage: .light, startTime: startTime.addingTimeInterval(10800), endTime: now)
        ]
        
        // Sample HR data
        let hrData = stride(from: 0, to: 8*60, by: 10).map { minutes in
            HeartRateDataPoint(
                timestamp: startTime.addingTimeInterval(TimeInterval(minutes * 60)),
                bpm: 55 + sin(Double(minutes) / 60 * .pi) * 12
            )
        }
        
        // Sample RR data
        let rrData = stride(from: 0, to: 8*60, by: 10).map { minutes in
            RespiratoryRateDataPoint(
                timestamp: startTime.addingTimeInterval(TimeInterval(minutes * 60)),
                breathsPerMinute: 14.5 + Double.random(in: -0.5...0.5)
            )
        }
        
        return NavigationView {
            ScrollView {
                EnhancedSleepTimeline(
                    stages: stages,
                    events: [],
                    startTime: startTime,
                    endTime: now,
                    heartRateData: hrData,
                    respiratoryRateData: rrData
                )
                .padding()
            }
            .navigationTitle("Sleep Timeline")
        }
    }
}
#endif
