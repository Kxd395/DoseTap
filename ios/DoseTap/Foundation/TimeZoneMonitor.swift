// Foundation/TimeZoneMonitor.swift
import Foundation
import Combine

final class TimeZoneMonitor: ObservableObject {
    static let shared = TimeZoneMonitor()
    @Published private(set) var lastChange: Date?

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lastChange = Date()
            // Hook: call into your DosingService to recalc tonight and reschedule.
            // Also log a lightweight `system` event if you want visibility in History.
            print("Time zone changed - triggering recalculation")
            self?.handleTimeZoneChange()
        })
        tokens.append(nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.lastChange = Date()
            // Optional: nightly maintenance (ensureScheduled()).
            print("Calendar day changed - triggering maintenance")
            self?.handleDayChange()
        })
    }
    
    private func handleTimeZoneChange() {
        // Log system event for traceability
        let store = EventStoreCoreData()
        store.insertEvent(
            id: UUID().uuidString,
            type: "system",
            source: "time_zone_monitor",
            occurredAtUTC: Date(),
            localTZ: TimeZone.current.identifier,
            doseSequence: nil,
            note: "Time zone changed to \(TimeZone.current.identifier)"
        )
        
        // Trigger UI update for travel mode interstitial
        NotificationCenter.default.post(name: .timeZoneChangeDetected, object: nil)
    }
    
    private func handleDayChange() {
        // Nightly maintenance placeholder
        print("Performing nightly maintenance")
    }
    
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

extension Notification.Name {
    static let timeZoneChangeDetected = Notification.Name("timeZoneChangeDetected")
}
