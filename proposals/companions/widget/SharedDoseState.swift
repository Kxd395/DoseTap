// SharedDoseState.swift — Shared state for WidgetKit + main app via App Group
// The main app writes; widgets read.
import Foundation

/// Lightweight snapshot of dose state for widgets to consume.
/// Written to App Group UserDefaults by the main app on every state change.
public struct SharedDoseState: Codable {
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    public let sessionDate: String
    public let updatedAt: Date

    public init(
        dose1Time: Date? = nil,
        dose2Time: Date? = nil,
        dose2Skipped: Bool = false,
        snoozeCount: Int = 0,
        sessionDate: String = "",
        updatedAt: Date = Date()
    ) {
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.sessionDate = sessionDate
        self.updatedAt = updatedAt
    }

    // MARK: - Phase computation (widget-side)

    public enum WidgetPhase: String {
        case noDose     = "Waiting for Dose 1"
        case waiting    = "Window not open yet"
        case windowOpen = "Take Dose 2"
        case complete   = "Both doses done"
        case skipped    = "Dose 2 skipped"
        case expired    = "Window expired"
    }

    public var phase: WidgetPhase {
        guard let d1 = dose1Time else { return .noDose }
        if dose2Skipped { return .skipped }
        if dose2Time != nil { return .complete }

        let elapsed = Date().timeIntervalSince(d1) / 60
        if elapsed < 150 { return .waiting }
        if elapsed <= 240 { return .windowOpen }
        return .expired
    }

    /// Minutes until the next interesting event (window open or window close).
    public var countdownMinutes: Int? {
        guard let d1 = dose1Time, dose2Time == nil, !dose2Skipped else { return nil }
        let elapsed = Date().timeIntervalSince(d1) / 60
        if elapsed < 150 { return Int(150 - elapsed) }
        if elapsed <= 240 { return Int(240 - elapsed) }
        return nil
    }

    // MARK: - App Group persistence

    /// App Group suite name. Must match the App Group configured in both targets.
    public static let appGroupSuite = "group.com.dosetap.shared"
    private static let stateKey = "SharedDoseState_v1"

    public static func load() -> SharedDoseState? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite),
              let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(SharedDoseState.self, from: data)
    }

    public func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }
}
