import SwiftUI

@main
@MainActor
struct DoseTapDashboardApp: App {
    @StateObject private var model: DashboardModel
    init() {
        #if DEBUG
        if let encoded = ProcessInfo.processInfo.environment["DOSETAP_DASHBOARD_UI_FIXTURE"],
           let bytes = Data(base64Encoded: encoded) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-report-\(UUID().uuidString).json")
            let testModel = DashboardModel(cacheURL: url)
            testModel.receive(bytes, context: testModel.connection.contextID)
            _model = StateObject(wrappedValue: testModel); return
        }
        #endif
        _model = StateObject(wrappedValue: DashboardModel())
    }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            DashboardRoot(model: model, connection: model.connection)
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.connection.stop() } }
        }
    }
}
