import UIKit
import WatchConnectivity

@main
class AppDelegate: UIResponder, UIApplicationDelegate, WCSessionDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.scheme == "dosetap" {
            if url.host == "log",
               let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let event = items.first(where: {$0.name == "event"})?.value {
                EventLogger.shared.handle(event: event)
                return true
            } else if url.host == "oauth" {
                WHOOPManager.shared.handleCallback(url: url)
                return true
            }
        }
        return false
    }

    // WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle activation
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Handle
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Handle
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let event = message["event"] as? String {
            EventLogger.shared.handle(event: event)
        }
    }
}
