import Foundation

// Test if EventStore.swift compiles independently
func testEventStore() {
    let store = JSONEventStore()
    let event = DoseEvent(type: .dose1)
    print("Event created: \(event)")
}
