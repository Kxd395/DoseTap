import Foundation
import HealthKit

final class UnifiedStore: ObservableObject {
    static let shared = UnifiedStore()
    private init() { loadDemoData() }

    @Published private(set) var records: [SavedDatum] = []
    @Published private(set) var initialConfig: DashboardConfig?

    // MARK: - Demo loader
    func loadDemoData() {
        guard records.isEmpty else { return }
        if let url = Bundle.main.url(forResource: "demo_data", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let arr = json["saved_data"] as? [[String: Any]] {
                        let decoded = try JSONDecoder().decode([SavedDatum].self, from: JSONSerialization.data(withJSONObject: arr))
                        self.records = decoded.sorted(by: { $0.timestamp < $1.timestamp })
                    }
                    // Parse dashboard config if present
                    if let dash = json["dashboard"],
                       let dashData = try? JSONSerialization.data(withJSONObject: dash) {
                        self.initialConfig = try? JSONDecoder().decode(DashboardConfig.self, from: dashData)
                    }
                } else if let arr = try? JSONDecoder().decode([SavedDatum].self, from: data) {
                    self.records = arr.sorted(by: { $0.timestamp < $1.timestamp })
                }
            } catch {
                print("UnifiedStore demo load error: \(error)")
            }
        }
    }

    // MARK: - Ingestors
    func ingestManualEvent(_ event: Event, userId: String = "u_kevin_dial") {
        let metric: DataMetric
        let val: String
        switch event.type {
        case .dose1: metric = .medication_event; val = "dose1"
        case .dose2: metric = .medication_event; val = "dose2"
        case .bathroom: metric = .bathroom_event; val = "out_of_bed"
        case .lights_out: metric = .sleep_stage; val = "lights_out"
        case .wake_final: metric = .sleep_stage; val = "awake_final"
        case .snooze: metric = .medication_event; val = "snooze"
        }
        let datum = SavedDatum(user_id: userId,
                               timestamp: event.ts,
                               source: .manual,
                               metric: metric,
                               valueString: val,
                               valueNumber: nil,
                               notes: "Event: \(event.type.rawValue)",
                               tags: ["app"])
        records.append(datum)
        records.sort { $0.timestamp < $1.timestamp }
        persist()
    }

    // Placeholder whoop/health ingestors if needed later
    func ingestWhoop(metric: DataMetric, value: Double, at date: Date, userId: String = "u_kevin_dial") {
        let datum = SavedDatum(user_id: userId, timestamp: date, source: .whoop, metric: metric, valueString: nil, valueNumber: value, notes: nil, tags: ["whoop"])
        records.append(datum); records.sort { $0.timestamp < $1.timestamp }; persist()
    }

    func ingestHealth(metric: DataMetric, value: Double, at date: Date, userId: String = "u_kevin_dial") {
        let datum = SavedDatum(user_id: userId, timestamp: date, source: .apple_health, metric: metric, valueString: nil, valueNumber: value, notes: nil, tags: ["apple_health"])
        records.append(datum); records.sort { $0.timestamp < $1.timestamp }; persist()
    }

    // MARK: - Filtering
    func filtered(_ f: DashboardFilters) -> [SavedDatum] {
        records.filter { d in
            d.timestamp >= f.dateStart && d.timestamp <= f.dateEnd &&
            f.sources.contains(d.source) &&
            f.metrics.contains(d.metric)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Persistence
    private func persist() {
        // Store to a single JSON file in Documents for demo purposes
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("unified.json")
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url)
        } catch {
            print("UnifiedStore persist error: \(error)")
        }
    }

    // MARK: - Imports (snapshots)
    @MainActor
    func importHealthSnapshot(hoursBack: Int = 12) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: end) ?? end.addingTimeInterval(-Double(hoursBack)*3600)
        do {
            try await HealthAccess.requestAuthorization()
        } catch {
            print("Health auth error: \(error)")
        }
        async let hr = try? HealthAccess.averageQuantity(type: HealthAccess.heartRateType, unit: HKUnit(from: "count/min"), start: start, end: end)
        async let rr = try? HealthAccess.averageQuantity(type: HealthAccess.respRateType, unit: HKUnit(from: "count/min"), start: start, end: end)
        async let spo2 = try? HealthAccess.averageQuantity(type: HealthAccess.spo2Type, unit: HKUnit.percent(), start: start, end: end)
        async let hrv = try? HealthAccess.averageQuantity(type: HealthAccess.hrvType, unit: HKUnit.secondUnit(with: .milli), start: start, end: end)
        let (avgHR, avgRR, avgSpO2, avgHRV) = await (hr, rr, spo2, hrv)
        let ts = Date()
        if let v = avgHR { ingestHealth(metric: .heart_rate, value: v, at: ts) }
        if let v = avgRR { ingestHealth(metric: .respiratory_rate, value: v, at: ts) }
        if let v = avgSpO2 { ingestHealth(metric: .oxygen_saturation, value: v, at: ts) }
        if let v = avgHRV { ingestHealth(metric: .hrv_sdnn, value: v, at: ts) }
    }

    @MainActor
    func importWhoopSnapshot(hoursBack: Int = 12) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: end) ?? end.addingTimeInterval(-Double(hoursBack)*3600)
        var vitals = await WHOOPManager.shared.fetchVitalsAverageConfigured(start: start, end: end)
        if vitals.hr == nil && vitals.rr == nil && vitals.spo2 == nil && vitals.hrv == nil {
            // Fallback to heuristic paths if config is missing or invalid
            vitals = await WHOOPManager.shared.fetchVitalsAverage(start: start, end: end)
        }
        let ts = Date()
        var ingested = 0
        if let v = vitals.hr { ingestWhoop(metric: .heart_rate, value: v, at: ts); ingested += 1 }
        if let v = vitals.rr { ingestWhoop(metric: .respiratory_rate, value: v, at: ts); ingested += 1 }
        if let v = vitals.spo2 { ingestWhoop(metric: .oxygen_saturation, value: v, at: ts); ingested += 1 }
        if let v = vitals.hrv { ingestWhoop(metric: .hrv_sdnn, value: v, at: ts); ingested += 1 }
        if ingested == 0 {
            // Fallback: log note if metrics unavailable
            let datum = SavedDatum(user_id: "u_kevin_dial",
                                   timestamp: ts,
                                   source: .whoop,
                                   metric: .sleep_stage,
                                   valueString: "imported_0_metrics",
                                   valueNumber: nil,
                                   notes: "WHOOP metrics unavailable for snapshot window",
                                   tags: ["whoop","import"])
            records.append(datum)
            records.sort { $0.timestamp < $1.timestamp }
            persist()
        }
    }
}
