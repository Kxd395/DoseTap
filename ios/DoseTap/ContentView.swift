import SwiftUI
import DoseCore
import HealthKit
import UIKit
import os.log

// MARK: - Main Tab View with Swipe Navigation
struct ContentView: View {
    @StateObject private var core = DoseTapCore()
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var eventLogger = EventLogger.shared
    @StateObject private var sessionRepo = SessionRepository.shared
    @StateObject private var undoState = UndoStateManager()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var alarmService = AlarmService.shared
    @ObservedObject private var urlRouter = URLRouter.shared
    @State private var sharedPageImage: UIImage?
    @State private var showPageShareSheet = false
    @State private var isPreparingPageShare = false
    @State private var pageShareErrorMessage: String?
    private let tabBarHeight: CGFloat = 64
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Swipeable Page View
            TabView(selection: $urlRouter.selectedTab) {
                LegacyTonightView(core: core, eventLogger: eventLogger, undoState: undoState)
                    .environmentObject(themeManager)
                    .tag(AppTab.tonight)
                
                DetailsView(core: core, eventLogger: eventLogger)
                    .environmentObject(themeManager)
                    .tag(AppTab.timeline)
                
                HistoryView()
                    .environmentObject(themeManager)
                    .tag(AppTab.history)

                DashboardTabView(core: core, eventLogger: eventLogger)
                    .environmentObject(themeManager)
                    .tag(AppTab.dashboard)
                
                SettingsView()
                    .environmentObject(themeManager)
                    .tag(AppTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarHeight)
            }
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $urlRouter.selectedTab)
                .frame(height: tabBarHeight)
            
            // Undo Snackbar Overlay
            UndoOverlayView(stateManager: undoState)
            
            // URL Action Feedback Banner
            VStack {
                URLFeedbackBanner()
                Spacer()
            }
            .padding(.top, 50)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        shareVisiblePage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 52, height: 52)
                            if isPreparingPageShare {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparingPageShare)
                    .accessibilityLabel("Share current page screenshot")
                }
                .padding(.top, 54)
                .padding(.trailing, 16)
                Spacer()
            }
        }
        .preferredColorScheme(themeManager.currentTheme == .night ? .dark : (themeManager.currentTheme.colorScheme ?? settings.colorScheme))
        .accentColor(themeManager.currentTheme.accentColor)
        .applyNightModeFilter(themeManager.currentTheme)
        .fullScreenCover(isPresented: $alarmService.isAlarmRinging) {
            AlarmRingingView()
        }
        .sheet(isPresented: $showPageShareSheet) {
            if let sharedPageImage {
                ActivityViewController(activityItems: [sharedPageImage])
            }
        }
        .alert("Unable to Share Screen", isPresented: Binding(
            get: { pageShareErrorMessage != nil },
            set: { if !$0 { pageShareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                pageShareErrorMessage = nil
            }
        } message: {
            Text(pageShareErrorMessage ?? "Unknown error.")
        }
        .onAppear {
            // P0 FIX: Wire DoseTapCore to SessionRepository (single source of truth)
            // All state reads/writes now go through SessionRepository
            core.setSessionRepository(sessionRepo)
            
            // Wire URLRouter dependencies for deep link handling
            urlRouter.core = core
            urlRouter.eventLogger = eventLogger
            
            // Setup undo callbacks
            setupUndoCallbacks()
        }
    }

    private func shareVisiblePage() {
        guard !isPreparingPageShare else { return }
        isPreparingPageShare = true
        pageShareErrorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let image = captureCurrentWindowScreenshot() {
                sharedPageImage = image
                showPageShareSheet = true
            } else {
                pageShareErrorMessage = "Could not capture the current screen."
            }
            isPreparingPageShare = false
        }
    }

    private func captureCurrentWindowScreenshot() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: keyWindow.bounds, format: format)
        return renderer.image { _ in
            keyWindow.drawHierarchy(in: keyWindow.bounds, afterScreenUpdates: true)
        }
    }
    
    private func setupUndoCallbacks() {
        // On commit: the action stays (do nothing, already saved)
        undoState.onCommit = { action in
            appLogger.info("Action committed: \(String(describing: action), privacy: .private)")
        }
        
        // On undo: revert the action
        undoState.onUndo = { action in
            Task { @MainActor in
                switch action {
                case .takeDose1(let time):
                    // Revert Dose 1
                    sessionRepo.clearDose1()
                    appLogger.info("Undid Dose 1 taken at \(time, privacy: .private)")
                    
                case .takeDose2(let time):
                    // Revert Dose 2
                    sessionRepo.clearDose2()
                    appLogger.info("Undid Dose 2 taken at \(time, privacy: .private)")
                    
                case .skipDose(let seq, _):
                    // Revert skip
                    sessionRepo.clearSkip()
                    appLogger.info("Undid skip of dose \(seq)")
                    
                case .snooze(let mins):
                    // Revert snooze (decrement count)
                    sessionRepo.decrementSnoozeCount()
                    appLogger.info("Undid snooze of \(mins) minutes")
                }
            }
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
        )
    }
}

