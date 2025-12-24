import Foundation

final class Store {
    static let shared = Store()
    private init() {}

    private var events: [Event] = []

    func add(_ e: Event) {
        events.append(e)
        persist()
    }

    func allEvents() -> [Event] { events }

    private func persist() {
        // Minimal JSON persistence for MVP
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("events.json")
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: url)
        } catch {
            print("Persist failed: \(error)")
        }
    }

    func exportToCSV() -> String? {
        var csv = "id,type,timestamp,source,meta\n"
        for event in events {
            let meta = event.meta.map { "\($0.key):\($0.value)" }.joined(separator: ";")
            csv += "\(event.id),\(event.type.rawValue),\(event.ts.ISO8601Format()),\(event.source),\(meta)\n"
        }
        return csv
    }
}
