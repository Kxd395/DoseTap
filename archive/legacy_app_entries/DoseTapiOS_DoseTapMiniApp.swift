import SwiftUI

@main
struct DoseTapMiniApp: App {
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
    
    var body: some View {
        VStack(spacing: 20) {
            Text("DoseTap Minimal")
                .font(.largeTitle)
                .padding()
            
            VStack(spacing: 16) {
                if dose1Time == nil {
                    Button("Take Dose 1") {
                        dose1Time = Date()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.headline)
                } else {
                    Text("Dose 1 taken at \(dose1Time!, formatter: timeFormatter)")
                        .foregroundColor(.green)
                    
                    Button("Take Dose 2") {
                        dose2Time = Date()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.headline)
                    
                    Button("Snooze 10m") {
                        snoozeCount += 1
                    }
                    .buttonStyle(.bordered)
                }
                
                if dose2Time != nil {
                    Text("Dose 2 taken at \(dose2Time!, formatter: timeFormatter)")
                        .foregroundColor(.green)
                    
                    Button("Reset") {
                        dose1Time = nil
                        dose2Time = nil
                        snoozeCount = 0
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    ContentView()
}
