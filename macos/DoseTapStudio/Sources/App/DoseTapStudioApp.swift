import SwiftUI

/// Main app entry point for DoseTap Studio
@main
struct DoseTapStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
