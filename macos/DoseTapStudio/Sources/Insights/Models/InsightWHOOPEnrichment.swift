import Foundation

struct InsightWHOOPEnrichment: Codable, Hashable, Sendable {
    let version: Int
    // Preserve future status strings without interpreting them as measurements.
    let sleepStatus: String
    let recoveryStatus: String
    let queryStartUTC: Date?
    let queryEndUTC: Date?
    let sleepRecordCount: Int?
    let recoveryRecordCount: Int?
    let eligibleNightCount: Int?
    let notAttemptedReason: String?
}
