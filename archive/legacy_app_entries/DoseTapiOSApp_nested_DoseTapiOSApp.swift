import SwiftUI

@main
struct DoseTapiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var dose1Time: Date? = nil
    @State private var dose2Time: Date? = nil
    @State private var snoozeCount: Int = 0
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("DoseTap")
                .font(.largeTitle)
                .padding()
            
            VStack(spacing: 16) {
                if dose1Time == nil {
                    Button("Take Dose 1") {
                        dose1Time = Date()
                    }
                    .font(.headline)
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("✅ Dose 1 taken")
                            .foregroundColor(.green)
                            .font(.headline)
                        
                        Text("at \(dose1Time!, formatter: timeFormatter)")
                            .foregroundColor(.secondary)
                        
                        if dose2Time == nil {
                            HStack(spacing: 16) {
                                Button("Take Dose 2") {
                                    dose2Time = Date()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Snooze (\(snoozeCount))") {
                                    snoozeCount += 1
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding()
                        } else {
                            VStack(spacing: 8) {
                                Text("✅ Dose 2 taken")
                                    .foregroundColor(.green)
                                    .font(.headline)
                                
                                Text("at \(dose2Time!, formatter: timeFormatter)")
                                    .foregroundColor(.secondary)
                                
                                Button("Reset Session") {
                                    dose1Time = nil
                                    dose2Time = nil
                                    snoozeCount = 0
                                }
                                .buttonStyle(.bordered)
                                .padding()
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
