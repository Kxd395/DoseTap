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
        let interval = ProcessInfo.processInfo.arguments.contains("--uitesting-nap-interval")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let captured = interval ? calendar.startOfDay(for: Date()).addingTimeInterval(-12 * 3600) : Date()
        if interval {
            let dose = captured.addingTimeInterval(-1800), end = captured.addingTimeInterval(-4500)
            if !storage.saveDose1(timestamp: dose, sessionId: "synthetic-nap-dose-session", sessionDateOverride: storage.sessionDateString(for: dose), sessionStart: dose).isCommitted {
                failure = "Synthetic administration could not be prepared."
            }
            do {
                if try repository.napDiary() == nil {
                    var document = NapDiaryDocument()
                    document.episodes = [.init(id: "synthetic-nap-ended", day: NapEpisode.day(end, "America/New_York"), timeZoneID: "America/New_York", start: end.addingTimeInterval(-1800), end: end, estimatedSleepMinutes: 20, recordedAt: captured)]
                    try repository.saveNapDiary(document, expectedRevision: nil)
                }
            } catch { failure = "Synthetic nap could not be prepared." }
        }
        self.failure = failure
        _model = StateObject(wrappedValue: DashboardAnalyticsModel(now: { captured }, sessionRepo: repository, timeZone: { TimeZone(secondsFromGMT: 0)! }))
    }
    var body: some View {
        NavigationStack {
            if let failure { Text(failure) }
            else { SleepNapsDashboardView(model: model).task { if ProcessInfo.processInfo.arguments.contains("--uitesting-nap-interval") { await model.refreshAndWait() } } }
        }
    }
}
#endif
