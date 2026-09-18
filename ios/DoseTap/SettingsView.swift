import SwiftUI

struct SettingsView: View {
    @Environment(\.isInSplitView) var isInSplitView
    @StateObject var settings = UserSettingsManager.shared
    @State var showingResetConfirmation = false
    @State var showingExportSuccess = false
    @State var exportArchive: StudioExportArchive?
    @State var isExporting = false
    @State var exportStatus = ""
    @State var requestedExportFormat: SettingsExportFormat = .studioBundle
    @State var showingExportError = false
    @State var exportErrorMessage = ""
    @State var showingNotificationPermissionAlert = false
    @State var notificationPermissionMessage = ""
    @ObservedObject var urlRouter = URLRouter.shared
    @ObservedObject var sleepPlanStore = SleepPlanStore.shared
    let tabBarInsetHeight: CGFloat = 64

    var body: some View {
        if isInSplitView {
            settingsContent
        } else {
            NavigationStack {
                settingsContent
            }
        }
    }
}

struct StudioExportArchive: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()

        SettingsView()
            .preferredColorScheme(.dark)

        NavigationView {
            EventCooldownSettingsView()
        }

        NavigationView {
            QuickLogCustomizationView()
        }
    }
}
