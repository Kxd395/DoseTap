import Foundation

/// Analytics summary computed from imported data
struct DoseTapAnalytics {
    let totalEvents: Int
    let totalSessions: Int
    let adherenceRate30d: Double      // Percentage of adherent sessions in last 30 days
    let averageWindow30d: Double      // Average dose window time in minutes
    let missedDoses30d: Int          // Number of missed doses in last 30 days
    let averageRecovery30d: Double?   // Average WHOOP recovery if available
    let averageHR30d: Double?        // Average heart rate if available
    
    static let empty = DoseTapAnalytics(
        totalEvents: 0,
        totalSessions: 0,
        adherenceRate30d: 0.0,
        averageWindow30d: 0.0,
        missedDoses30d: 0,
        averageRecovery30d: nil,
        averageHR30d: nil
    )
    
    /// Get adherence status text
    var adherenceStatusText: String {
        switch adherenceRate30d {
        case 95...100: return "Excellent (≥95%)"
        case 85..<95: return "Good (85-94%)"
        case 70..<85: return "Fair (70-84%)"
        default: return "Needs Attention (<70%)"
        }
    }
    
    /// Get adherence color
    var adherenceColor: String {
        switch adherenceRate30d {
        case 95...100: return "green"
        case 85..<95: return "blue"
        case 70..<85: return "orange"
        default: return "red"
        }
    }
    
    /// Get window timing status
    var windowStatusText: String {
        switch averageWindow30d {
        case 150...180: return "Optimal Window"
        case 181...210: return "Good Window"
        case 211...240: return "Late Window"
        default: return averageWindow30d < 150 ? "Early Window" : "Missed Window"
        }
    }
}
