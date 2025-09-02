import SwiftUI
import WatchConnectivity

@main
struct DoseTapWatchApp: App {
    @WKApplicationDelegateAdaptor var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class WatchAppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate {
    func applicationDidFinishLaunching() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle activation
    }
}
