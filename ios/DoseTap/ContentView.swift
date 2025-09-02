import SwiftUI

struct ContentView: View {
    @State private var lastMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("DoseTap")
                .font(.largeTitle).bold()

            HStack {
                Button("Log Dose 1") { EventLogger.shared.handle(event: "dose1"); lastMessage = "Dose 1 logged" }
                    .buttonStyle(.borderedProminent)

                Button("Log Dose 2") { EventLogger.shared.handle(event: "dose2"); lastMessage = "Dose 2 logged" }
                    .buttonStyle(.bordered)
            }

            Button("Bathroom / Out-of-Bed") { EventLogger.shared.handle(event: "bathroom"); lastMessage = "Bathroom logged" }
                .buttonStyle(.bordered)

            Button("Snooze Reminder") { EventLogger.shared.handle(event: "snooze"); lastMessage = "Reminder snoozed" }
                .buttonStyle(.bordered)

            Button("Connect WHOOP") { WHOOPManager.shared.authorize(); lastMessage = "Opening WHOOP auth" }
                .buttonStyle(.bordered)

            if !lastMessage.isEmpty {
                Text(lastMessage).foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
