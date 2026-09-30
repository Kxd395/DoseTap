#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import DoseCore
@MainActor
struct SleepNapsFixtureView: View {
    @StateObject private var model: DashboardAnalyticsModel
    private let failure: String?
    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dosetap-synthetic-nap-fixture", isDirectory: true)
        var failure: String?
        do {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-nap-reset"), FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch { failure = "Synthetic fixture directory could not be prepared." }
        let storage = EventStorage(dbPath: folder.appendingPathComponent("synthetic-naps.sqlite").path)
        let repository = SessionRepository(storage: storage)
        self.failure = failure
        _model = StateObject(wrappedValue: DashboardAnalyticsModel(sessionRepo: repository, timeZone: { TimeZone(secondsFromGMT: 0)! }))
    }
    var body: some View {
        NavigationStack {
            if let failure { Text(failure) }
            else { SleepNapsDashboardView(model: model) }
        }
    }
}
#endif
