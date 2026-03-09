import SwiftUI

struct SettingsView: View {
    @Environment(\.isInSplitView) var isInSplitView
    @StateObject var settings = UserSettingsManager.shared
    @State var showingResetConfirmation = false
    @State var showingExportSuccess = false
    @State var showingExportSheet = false
    @State var showingExportError = false
    @State var exportErrorMessage = ""
    @State var showingNotificationPermissionAlert = false
    @State var notificationPermissionMessage = ""
    @State var exportURL: URL?
    @ObservedObject var urlRouter = URLRouter.shared
    @ObservedObject var sleepPlanStore = SleepPlanStore.shared
    let tabBarInsetHeight: CGFloat = 64

    var body: some View {
        if isInSplitView {
            settingsContent
        } else {
            NavigationView {
                settingsContent
            }
        }
    }
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
