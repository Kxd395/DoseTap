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
    
    @StateObject private var viewModel = WatchDoseViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

#if canImport(WatchConnectivity)
class WatchAppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate {
    
    func applicationDidFinishLaunching() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            print("✅ WatchConnectivity activated")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("❌ WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("✅ WCSession activated: \(activationState.rawValue)")
        }
    }
    
    /// Receive message from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }
    
    /// Receive message with reply handler
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingMessage(message)
        
        // Send acknowledgment
        replyHandler(["status": "received"])
    }
    
    /// Receive application context (background sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingMessage(applicationContext)
    }
    
    /// Receive user info (queued transfers)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingMessage(userInfo)
    }
    
    private func handleIncomingMessage(_ message: [String: Any]) {
        // Parse sync state from iPhone
        Task { @MainActor in
            if message["syncType"] as? String == "state" {
                // Full state sync from phone
                NotificationCenter.default.post(
                    name: .watchDidReceiveStateSync,
                    object: nil,
                    userInfo: message
                )
            }
        }
        print("📥 Received from iPhone: \(message)")
    }
}
#endif

// MARK: - Notification for state sync
extension Notification.Name {
    static let watchDidReceiveStateSync = Notification.Name("watchDidReceiveStateSync")
}
#endif
