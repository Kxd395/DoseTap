import SwiftUI
import Foundation

// Simple persistent event storage
struct DoseEvent: Codable, Identifiable {
    let id = UUID()
    let type: String
    let timestamp: Date
    
    var displayText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(type) - \(formatter.string(from: timestamp))"
    }
}

class EventStorage: ObservableObject {
    @Published var events: [DoseEvent] = []
    private let fileURL: URL
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documentsPath.appendingPathComponent("dose_events.json")
        loadEvents()
    }
    
    func addEvent(type: String) {
        let event = DoseEvent(type: type, timestamp: Date())
        events.append(event)
        saveEvents()
    }
    
    private func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL)
            print("Events saved to: \(fileURL.path)")
        } catch {
            print("Failed to save events: \(error)")
        }
    }
    
    private func loadEvents() {
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode([DoseEvent].self, from: data)
            print("Loaded \(events.count) events from: \(fileURL.path)")
        } catch {
            print("Failed to load events (starting fresh): \(error)")
            events = []
        }
    }
    
    func getStorageLocation() -> String {
        return fileURL.path
    }
}

struct ContentView: View {
    @StateObject private var storage = EventStorage()
    @State private var lastMessage: String = "DoseTap Ready"
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("DoseTap")
                    .font(.largeTitle).bold()

                Text(lastMessage)
                    .foregroundColor(.secondary)
                    .padding()

                HStack {
                    Button("Log Dose 1") {
                        storage.addEvent(type: "Dose 1")
                        let timestamp = formatTime(Date())
                        lastMessage = "Dose 1 logged at \(timestamp)"
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Log Dose 2") {
                        storage.addEvent(type: "Dose 2")
                        let timestamp = formatTime(Date())
                        lastMessage = "Dose 2 logged at \(timestamp)"
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("Snooze") {
                        storage.addEvent(type: "Snooze")
                        let timestamp = formatTime(Date())
                        lastMessage = "Snoozed at \(timestamp)"
                    }
                    .buttonStyle(.bordered)

                    Button("Bathroom") {
                        storage.addEvent(type: "Bathroom")
                        let timestamp = formatTime(Date())
                        lastMessage = "Bathroom logged at \(timestamp)"
                    }
                    .buttonStyle(.bordered)
                }

                // Display recent events
                if !storage.events.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Events:")
                            .font(.headline)
                            .padding(.top)
                        
                        ForEach(storage.events.suffix(3).reversed()) { event in
                            Text(event.displayText)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()

                HStack {
                    Button("Settings") {
                        showSettings = true
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("History") {
                        showHistory = true
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 16) {
                Text("Settings")
                    .font(.title2)
                    .padding()
                
                Text("Data stored at:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(storage.getStorageLocation())
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding()
                
                Text("Total Events: \(storage.events.count)")
                    .font(.caption)
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showHistory) {
            VStack(spacing: 16) {
                Text("Event History")
                    .font(.title2)
                    .padding()
                
                if storage.events.isEmpty {
                    Text("No events logged yet")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(storage.events.reversed()) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.type)
                                    .font(.headline)
                                Text(event.timestamp, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(event.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
