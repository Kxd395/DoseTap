import Foundation

enum LogEvent: String, Codable {
    case dose1, dose2, bathroom, lights_out, wake_final, snooze
}

struct Event: Codable, Identifiable {
    var id = UUID()
    var type: LogEvent
    var ts: Date = Date()
    var source: String = "app" // btn|watch|app
    var meta: [String:String] = [:]
}
