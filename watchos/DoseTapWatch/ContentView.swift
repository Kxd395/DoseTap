import SwiftUI
import WatchConnectivity

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Button("Dose 1") { send(event: "dose1") }
                .buttonStyle(.borderedProminent)
            Button("Dose 2") { send(event: "dose2") }
            Button("Bathroom") { send(event: "bathroom") }
            Button("Snooze") { send(event: "snooze") }
        }.padding()
    }

    private func send(event: String) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["event": event], replyHandler: nil, errorHandler: { error in
                print("Send failed: \(error)")
            })
        } else {
            print("iPhone not reachable")
        }
    }
}ruct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Button("Dose 1") { send(url: "dosetap://log?event=dose1") }
                .buttonStyle(.borderedProminent)
            Button("Dose 2") { send(url: "dosetap://log?event=dose2") }
            Button("Bathroom") { send(url: "dosetap://log?event=bathroom") }
        }.padding()
    }

    private func send(url: String) {
        // In practice, use WatchConnectivity to message the iPhone app to open the URL internally.
        // Placeholder here.
        print("Would send URL: \(url)")
    }
}
