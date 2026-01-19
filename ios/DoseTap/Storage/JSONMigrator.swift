// Storage/JSONMigrator.swift
import Foundation

struct JSONMigrator {
    struct JSONDoseEvent: Decodable {
        let event_id: String, event_type: String, source: String
        let occurred_at_utc: Date, local_tz: String
        let dose_sequence: Int?
        let note: String?
    }
    struct JSONDoseSession: Decodable {
        let session_id: String, started_utc: Date
        let ended_utc: Date?
        let bedtime_local: String?
        let window_target_min: Int?
        let window_actual_min: Int?
        let adherence_flag: String?
        let whoop_recovery: Int?
        let avg_hr: Double?
        let sleep_efficiency: Double?
        let note: String?
    }

    static func runIfNeeded(baseURL: URL) {
        let flagKey = "didMigrateToCoreData"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
