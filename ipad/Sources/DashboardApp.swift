import SwiftUI

@main
struct DoseTapDashboardApp: App {
    @StateObject private var model = DashboardModel()
    var body: some Scene {
        WindowGroup { Text("DoseTap Dashboard · Read-only reporting") }
    }
}
