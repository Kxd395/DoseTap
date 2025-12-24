import Foundation

public struct NightSummary {
    public let minutesToFirstWake: Int?
    public let disturbancesScore: Double?
    public init(minutesToFirstWake: Int?, disturbancesScore: Double?) { self.minutesToFirstWake = minutesToFirstWake; self.disturbancesScore = disturbancesScore }
}

public struct RecommendationEngine {
    /// Returns minutes after Dose 1 for second-dose reminder, constrained to 150–240 with baseline clamp 165–210.
    public static func recommendOffsetMinutes(history: [NightSummary], liveSignals: (isLightOrAwakeNow: Bool, minutesSinceDose1: Int)?) -> Int {
        let lower = 150, upper = 240
        let samples = history.compactMap { $0.minutesToFirstWake }.filter { $0 >= lower && $0 <= upper }
        let baseline: Int = {
            guard !samples.isEmpty else { return 165 }
            let sorted = samples.sorted(); let mid = sorted.count / 2
            let median = sorted.count % 2 == 0 ? (sorted[mid-1] + sorted[mid]) / 2 : sorted[mid]
            return max(min(median, 210), 165)
        }()
        var target = baseline
        if let live = liveSignals {
            if live.isLightOrAwakeNow && (lower...upper).contains(live.minutesSinceDose1) {
                target = live.minutesSinceDose1
            } else if live.minutesSinceDose1 < 180 {
                target = min(target + 10, upper)
            }
        }
        return max(min(target, upper), lower)
    }
}
