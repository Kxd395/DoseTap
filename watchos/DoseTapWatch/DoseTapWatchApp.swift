// Entire file only compiles for watchOS to avoid availability noise during macOS test builds.
#if os(watchOS)
import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@main
@available(watchOS 9.0, *)
struct DoseTapWatchApp: App {
    #if canImport(WatchConnectivity)
    @WKApplicationDelegateAdaptor var appDelegate: WatchAppDelegate
    #endif
    var body: some Scene { WindowGroup { ContentView() } }
}

#if canImport(WatchConnectivity)
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
#endif
#endif
