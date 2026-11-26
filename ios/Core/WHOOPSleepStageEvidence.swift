import Foundation

/// Original aggregate stage amounts and score provenance. These do not establish
/// interval coverage or observed wake transitions, even when scored sleep is zero.
public struct WHOOPSleepStageEvidence: Codable, Equatable, Sendable {
    public let sleepID: String?
    public let scoreState: String?
    public let lightMilliseconds: Int?
    public let deepMilliseconds: Int?
    public let remMilliseconds: Int?
    public let version: Int?
    public let provenance: String?
    private static let source = "whoop.v2.activity.sleep.score.stage_summary"

    public init(sleepID: String?, scoreState: String?, lightMilliseconds: Int?, deepMilliseconds: Int?, remMilliseconds: Int?) {
        self.sleepID = sleepID; self.scoreState = scoreState; self.lightMilliseconds = lightMilliseconds
        self.deepMilliseconds = deepMilliseconds; self.remMilliseconds = remMilliseconds
        version = 1; provenance = Self.source
    }

    public var sleepMinutes: Double? {
        guard let sleepID, !sleepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              version == 1, provenance == Self.source, scoreState?.uppercased() == "SCORED",
              let light = lightMilliseconds, let deep = deepMilliseconds, let rem = remMilliseconds,
              light >= 0, deep >= 0, rem >= 0 else { return nil }
        // Convert before adding to avoid Int overflow; do not truncate each stage to minutes.
        let value = (Double(light) + Double(deep) + Double(rem)) / 60_000
        return value.isFinite ? value : nil
    }
}
