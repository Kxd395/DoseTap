import SwiftUI
import Charts
import Combine

struct HistoryView: View {
    @ObservedObject var store = UnifiedStore.shared

    // Persisted filter state
    @AppStorage("dash_merged") private var savedMerged: Bool = true
    // Per-view persisted selections
    @AppStorage("dash_sources") private var savedSources_legacy: String = "whoop,apple_health,manual"
    @AppStorage("dash_metrics") private var savedMetrics_legacy: String = "heart_rate,respiratory_rate,oxygen_saturation,hrv_sdnn,sleep_stage,medication_event,bathroom_event"
    @AppStorage("dash_sources_merged") private var savedSourcesMerged: String = "whoop,apple_health,manual"
    @AppStorage("dash_sources_compare") private var savedSourcesCompare: String = "whoop,apple_health"
    @AppStorage("dash_metrics_merged") private var savedMetricsMerged: String = "heart_rate,respiratory_rate,oxygen_saturation,hrv_sdnn,sleep_stage,medication_event,bathroom_event"
    @AppStorage("dash_metrics_compare") private var savedMetricsCompare: String = "heart_rate,respiratory_rate,oxygen_saturation,hrv_sdnn"
    @AppStorage("dash_start") private var savedStartISO: String = {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-12*3600))
    }()
    @AppStorage("dash_end") private var savedEndISO: String = {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(6*3600))
    }()

    @State private var mergedView = true
    @State private var selectedSources: Set<DataSource> = Set(DataSource.allCases)
    @State private var selectedMetrics: Set<DataMetric> = Set(DataMetric.allCases)
    @State private var dateStart: Date = Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? Date().addingTimeInterval(-12*3600)
    @State private var dateEnd: Date = Date().addingTimeInterval(6*3600)

    @State private var showHealthPrompt = false
    @State private var showWhoopPrompt = false

    var filters: DashboardFilters {
        DashboardFilters(dateStart: dateStart, dateEnd: dateEnd, sources: selectedSources, metrics: selectedMetrics)
    }

    var body: some View {
        VStack(spacing: 12) {
            headerControls
            counters
            errorPrompts
            if mergedView {
                mergedList
            } else {
                comparisonView
            }
        }
        .onAppear {
            UnifiedStore.shared.loadDemoData()
            applyInitialDashboardConfigIfNeeded()
            showWhoopPrompt = !WHOOPManager.shared.isAuthenticated()
            let status = HealthAccess.store.authorizationStatus(for: HealthAccess.sleepType)
            showHealthPrompt = status != .sharingAuthorized
            // Load persisted filters if no initial config was applied
            applyPersistedFiltersIfNeeded()
        }
        .onChange(of: mergedView) { new in savedMerged = new; loadViewSpecificPersistedFilters() }
        .onChange(of: selectedSources) { _ in persistCurrentSelections() }
        .onChange(of: selectedMetrics) { _ in persistCurrentSelections() }
        .onChange(of: dateStart) { new in savedStartISO = ISO8601DateFormatter().string(from: new) }
        .onChange(of: dateEnd) { new in savedEndISO = ISO8601DateFormatter().string(from: new) }
        .padding()
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    @State private var didApplyConfig = false
    private func applyInitialDashboardConfigIfNeeded() {
        guard !didApplyConfig, let cfg = store.initialConfig else { return }
        didApplyConfig = true
        if let merged = cfg.visualization?.merged_view { mergedView = merged }
        if let dr = cfg.filters?.date_range, dr.count == 2 {
            let fmt = ISO8601DateFormatter()
            if let s = fmt.date(from: dr[0]) { dateStart = s }
            if let e = fmt.date(from: dr[1]) { dateEnd = e }
        }
        if let sources = cfg.filters?.source {
            let mapped = sources.compactMap { DataSource.from($0) }
            if !mapped.isEmpty { selectedSources = Set(mapped) }
        }
        if let metrics = cfg.filters?.metric {
            let mapped = metrics.compactMap { DataMetric.from($0) }
            if !mapped.isEmpty { selectedMetrics = Set(mapped) }
        }
    }

    private func applyPersistedFiltersIfNeeded() {
        guard !didApplyConfig else { return } // config wins on first run
        mergedView = savedMerged
        loadViewSpecificPersistedFilters()
        let fmt = ISO8601DateFormatter()
        if let ds = fmt.date(from: savedStartISO) { dateStart = ds }
        if let de = fmt.date(from: savedEndISO) { dateEnd = de }
    }

    private func loadViewSpecificPersistedFilters() {
        let srcStr = mergedView ? savedSourcesMerged : savedSourcesCompare
        let metStr = mergedView ? savedMetricsMerged : savedMetricsCompare
        var srcs = srcStr.split(separator: ",").compactMap { DataSource(rawValue: String($0)) }
        var mets = metStr.split(separator: ",").compactMap { DataMetric(rawValue: String($0)) }
        // Fallback to legacy if any set is empty
        if srcs.isEmpty { srcs = savedSources_legacy.split(separator: ",").compactMap { DataSource(rawValue: String($0)) } }
        if mets.isEmpty { mets = savedMetrics_legacy.split(separator: ",").compactMap { DataMetric(rawValue: String($0)) } }
        if !srcs.isEmpty { selectedSources = Set(srcs) }
        if !mets.isEmpty { selectedMetrics = Set(mets) }
    }

    private func persistCurrentSelections() {
        let srcStr = selectedSources.map { $0.rawValue }.joined(separator: ",")
        let metStr = selectedMetrics.map { $0.rawValue }.joined(separator: ",")
        if mergedView {
            savedSourcesMerged = srcStr
            savedMetricsMerged = metStr
        } else {
            savedSourcesCompare = srcStr
            savedMetricsCompare = metStr
        }
        // Maintain legacy keys for backward compatibility
        savedSources_legacy = srcStr
        savedMetrics_legacy = metStr
    }

    private var headerControls: some View {
        VStack(spacing: 8) {
            // View mode
            HStack {
                Picker("Mode", selection: $mergedView) {
                    Text("Merged").tag(true)
                    Text("Compare").tag(false)
                }
                .pickerStyle(.segmented)
            }

            // Date range
            HStack {
                DatePicker("Start", selection: $dateStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $dateEnd, displayedComponents: [.date, .hourAndMinute])
            }

            // Sources
            HStack(spacing: 8) {
                ForEach(DataSource.allCases) { src in
                    Toggle(src.rawValue.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                        get: { selectedSources.contains(src) },
                        set: { isOn in
                            if isOn { _ = selectedSources.insert(src) }
                            else { selectedSources.remove(src) }
                        }
                    ))
                    .toggleStyle(.button)
                }
            }

            // Metrics menu
            Menu {
                ForEach(DataMetric.allCases) { m in
                    Button {
                        if selectedMetrics.contains(m) { selectedMetrics.remove(m) } else { selectedMetrics.insert(m) }
                    } label: {
                        Label(m.rawValue.replacingOccurrences(of: "_", with: " "), systemImage: selectedMetrics.contains(m) ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                Label("Metrics (\(selectedMetrics.count))", systemImage: "slider.horizontal.3")
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
    }

    private var errorPrompts: some View {
        VStack(spacing: 8) {
            if showHealthPrompt {
                GroupBox {
                    HStack {
                        Text("Apple Health permission needed")
                        Spacer()
                        Button("Grant Access") {
                            Task { try? await HealthAccess.requestAuthorization(); showHealthPrompt = false }
                        }
                    }
                }
            }
            if showWhoopPrompt {
                GroupBox {
                    HStack {
                        Text("WHOOP not connected")
                        Spacer()
                        Button("Reconnect WHOOP") { WHOOPManager.shared.authorize() }
                    }
                }
            }
        }
    }

    private var mergedList: some View {
        let data = store.filtered(filters)
        return List(data) { d in
            HStack(alignment: .top, spacing: 12) {
                Text(d.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(prettyMetric(d.metric)).bold()
                        Spacer()
                        Text(d.displayValue)
                    }
                    HStack(spacing: 8) {
                        sourceBadge(d.source)
                        if let notes = d.notes, !notes.isEmpty { Text(notes).foregroundColor(.secondary) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var comparisonView: some View {
        let data = store.filtered(filters)
        let focusMetrics: [DataMetric] = [.heart_rate, .respiratory_rate, .oxygen_saturation, .hrv_sdnn]
        let filtered = data.filter { focusMetrics.contains($0.metric) && $0.valueNumber != nil }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(focusMetrics, id: \.self) { metric in
                    let points = filtered.filter { $0.metric == metric }
                    if !points.isEmpty {
                        GroupBox(prettyMetric(metric)) {
                            // Summary chips
                            let stats = metricStats(points)
                            HStack(spacing: 8) {
                                Label(String(format: "min %.1f", stats.min), systemImage: "arrow.down")
                                Label(String(format: "med %.1f", stats.median), systemImage: "line.horizontal.3")
                                Label(String(format: "max %.1f", stats.max), systemImage: "arrow.up")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Chart(points, id: \.id) { d in
                                if let y = yValue(for: d) {
                                    LineMark(
                                        x: .value("Time", d.timestamp),
                                        y: .value("Value", y),
                                        series: .value("Source", d.source.rawValue)
                                    )
                                    .foregroundStyle(by: .value("Source", d.source.rawValue))
                                    .symbol(by: .value("Source", d.source.rawValue))
                                }
                            }
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                            .frame(height: 180)
                        }
                    }
                }
            }
        }
    }

    private func sourceBadge(_ s: DataSource) -> some View {
        Text(s.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(badgeColor(s))
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func badgeColor(_ s: DataSource) -> Color {
        switch s {
        case .whoop: return .purple
        case .apple_health: return .green
        case .manual: return .blue
        }
    }

    private func prettyMetric(_ m: DataMetric) -> String {
        switch m {
        case .heart_rate: return "Heart Rate"
        case .respiratory_rate: return "Respiratory Rate"
        case .oxygen_saturation: return "SpO₂ (%)"
        case .hrv_sdnn: return "HRV (SDNN)"
        case .sleep_stage: return "Sleep Stage"
        case .medication_event: return "Medication Event"
        case .bathroom_event: return "Bathroom Event"
        }
    }

    private func yValue(for d: SavedDatum) -> Double? {
        guard var v = d.valueNumber else { return nil }
        if d.metric == .oxygen_saturation { v *= 100 } // convert 0–1 → percent
        return v
    }

    private func metricStats(_ items: [SavedDatum]) -> (min: Double, median: Double, max: Double) {
        let ys: [Double] = items.compactMap { d in
            var v = d.valueNumber
            if d.metric == .oxygen_saturation, let n = v { v = n * 100 }
            return v
        }
        guard !ys.isEmpty else { return (0,0,0) }
        let sorted = ys.sorted()
        let minv = sorted.first!
        let maxv = sorted.last!
        let mid = sorted.count / 2
        let med = sorted.count % 2 == 0 ? (sorted[mid-1] + sorted[mid]) / 2.0 : sorted[mid]
        return (minv, med, maxv)
    }

    private var counters: some View {
        let data = store.filtered(filters)
        let total = data.count
        let whoop = data.filter { $0.source == .whoop }.count
        let health = data.filter { $0.source == .apple_health }.count
        let manual = data.filter { $0.source == .manual }.count
        let spanText: String = {
            guard let first = data.first?.timestamp, let last = data.last?.timestamp, last > first else { return "Span: 0m" }
            let mins = TimeIntervalMath.minutesBetween(start: first, end: last)
            let hours = mins / 60
            let rem = mins % 60
            return hours > 0 ? String(format: "Span: %dh %dm", hours, rem) : "Span: \(mins)m"
        }()
        return HStack(spacing: 12) {
            Label("Total: \(total)", systemImage: "list.number")
            Text(spanText)
            Spacer()
            sourceBadge(.whoop); Text("\(whoop)")
            sourceBadge(.apple_health); Text("\(health)")
            sourceBadge(.manual); Text("\(manual)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}
