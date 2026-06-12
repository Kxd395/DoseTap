import SwiftUI
import DoseCore
import HealthKit
import UIKit
import os.log

// MARK: - Main Tab View with Swipe Navigation
struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: UserSettingsManager
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var urlRouter = URLRouter.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sharedPageImage: UIImage?
    @State private var showPageShareSheet = false
    @State private var isPreparingPageShare = false
    @State private var pageShareErrorMessage: String?
    @State private var isSidebarVisible: NavigationSplitViewVisibility = .automatic
    private let tabBarHeight: CGFloat = 64

    /// `true` when running on iPad or in a regular-width environment (e.g. large iPhone landscape).
    private var usesSplitView: Bool { horizontalSizeClass == .regular }
    private var showsFloatingShareButton: Bool { urlRouter.selectedTab != .timeline }
    private var core: DoseTapCore { container.core }
    private var doseCoordinator: DoseActionCoordinator { container.doseCoordinator }
    private var eventLogger: EventLogger { container.eventLogger }
    private var undoState: UndoStateManager { container.undoState }
    private var sessionRepo: SessionRepository { container.sessionRepository }
    private var alarmService: AlarmService { container.alarmService }
    
    var body: some View {
        Group {
            if usesSplitView {
                iPadBody
            } else {
                compactBody
            }
        }
        .preferredColorScheme(themeManager.currentTheme == .night ? .dark : (themeManager.currentTheme.colorScheme ?? settings.colorScheme))
        .accentColor(themeManager.currentTheme.accentColor)
        .applyNightModeFilter(themeManager.currentTheme)
        .fullScreenCover(isPresented: Binding(
            get: { alarmService.isAlarmRinging },
            set: { alarmService.isAlarmRinging = $0 }
        )) {
            AlarmRingingView()
        }
        .sheet(isPresented: $showPageShareSheet) {
            if let sharedPageImage {
                CapturePreviewSheet(
                    title: "Full Screen Capture",
                    image: sharedPageImage
                ) {
                    self.sharedPageImage = nil
                    self.showPageShareSheet = false
                }
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
    }

    // MARK: - iPad / Regular Width Layout (NavigationSplitView)

    private var iPadBody: some View {
        NavigationSplitView(columnVisibility: $isSidebarVisible) {
            AdaptiveSidebarView(selectedTab: $urlRouter.selectedTab)
        } detail: {
            NavigationStack {
                detailContent(for: urlRouter.selectedTab)
                    .environment(\.isInSplitView, true)
            }
            .overlay(alignment: .topTrailing) {
                if showsFloatingShareButton {
                    shareButton
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                }
            }
        }
        // Undo Snackbar Overlay (iPad)
        .overlay(alignment: .bottom) {
            UndoOverlayView(stateManager: undoState)
        }
        // URL Action Feedback Banner (iPad)
        .overlay(alignment: .top) {
            URLFeedbackBanner()
                .padding(.top, 50)
        }
    }

    /// Returns the content view for the given tab, suitable for the NavigationSplitView detail column.
    @ViewBuilder
    private func detailContent(for tab: AppTab) -> some View {
        switch tab {
        case .tonight:
            LegacyTonightView(core: core, eventLogger: eventLogger, undoState: undoState, coordinator: doseCoordinator)
                .environmentObject(themeManager)
                .environmentObject(undoState)
        case .timeline:
            DetailsView(core: core, eventLogger: eventLogger)
                .environmentObject(themeManager)
                .environmentObject(undoState)
        case .history:
            HistoryView()
                .environmentObject(themeManager)
        case .dashboard:
            DashboardTabView(core: core, eventLogger: eventLogger)
                .environmentObject(themeManager)
        case .settings:
            SettingsView()
                .environmentObject(themeManager)
        }
    }

    // MARK: - Compact Layout (iPhone TabView - unchanged)

    private var compactBody: some View {
        ZStack(alignment: .bottom) {
            // Swipeable Page View
            TabView(selection: $urlRouter.selectedTab) {
                LegacyTonightView(core: core, eventLogger: eventLogger, undoState: undoState, coordinator: doseCoordinator)
                    .environmentObject(themeManager)
                    .environmentObject(undoState)
                    .tag(AppTab.tonight)
                
                DetailsView(core: core, eventLogger: eventLogger)
                    .environmentObject(themeManager)
                    .environmentObject(undoState)
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
                    if showsFloatingShareButton {
                        shareButton
                    }
                }
                .padding(.top, 54)
                .padding(.trailing, 16)
                Spacer()
            }
        }
    }

    // MARK: - Shared Components

    private var shareButton: some View {
        Button {
            shareCurrentPage()
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
        .accessibilityLabel("Share current page capture")
    }

    private func shareCurrentPage() {
        guard !isPreparingPageShare else { return }
        isPreparingPageShare = true
        pageShareErrorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let image = AppScreenCapture.captureActivePage() {
                sharedPageImage = image
                showPageShareSheet = true
            } else {
                pageShareErrorMessage = "Could not capture the current app screen."
            }
            isPreparingPageShare = false
        }
    }
}

enum AppScreenCapture {
    static func captureActivePage() -> UIImage? {
        guard let keyWindow = activeKeyWindow() else {
            return nil
        }

        keyWindow.layoutIfNeeded()

        if let scrollView = bestFullPageScrollView(in: keyWindow),
           let image = captureFullContent(of: scrollView) {
            return image
        }

        return captureVisibleWindow(keyWindow)
    }

    static func bestFullPageScrollView(in rootView: UIView) -> UIScrollView? {
        scrollViews(in: rootView)
            .filter { isFullPageCandidate($0, in: rootView) }
            .max { lhs, rhs in
                let lhsOverflow = lhs.contentSize.height - lhs.bounds.height
                let rhsOverflow = rhs.contentSize.height - rhs.bounds.height
                if lhsOverflow == rhsOverflow {
                    return lhs.contentSize.height < rhs.contentSize.height
                }
                return lhsOverflow < rhsOverflow
            }
    }

    private static func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }

    private static func scrollViews(in rootView: UIView) -> [UIScrollView] {
        var results: [UIScrollView] = []
        if let scrollView = rootView as? UIScrollView {
            results.append(scrollView)
        }
        for subview in rootView.subviews {
            results.append(contentsOf: scrollViews(in: subview))
        }
        return results
    }

    private static func isFullPageCandidate(_ scrollView: UIScrollView, in rootView: UIView) -> Bool {
        guard !scrollView.isHidden,
              scrollView.alpha > 0.01,
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0,
              scrollView.contentSize.width > 0,
              scrollView.contentSize.height > scrollView.bounds.height + 8 else {
            return false
        }

        let rectInRoot = scrollView.convert(scrollView.bounds, to: rootView)
        guard rectInRoot.intersects(rootView.bounds),
              rectInRoot.width >= rootView.bounds.width * 0.45 else {
            return false
        }

        let horizontalPagingOnly = scrollView.contentSize.width > scrollView.bounds.width * 1.5
            && scrollView.contentSize.height <= scrollView.bounds.height + 8
        return !horizontalPagingOnly
    }

    private static func captureFullContent(of scrollView: UIScrollView) -> UIImage? {
        let contentSize = scrollView.contentSize
        guard contentSize.width > 0, contentSize.height > 0 else {
            return nil
        }

        let originalOffset = scrollView.contentOffset
        let originalFrame = scrollView.frame
        let originalBounds = scrollView.bounds
        let originalShowsVertical = scrollView.showsVerticalScrollIndicator
        let originalShowsHorizontal = scrollView.showsHorizontalScrollIndicator

        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentOffset = .zero
        scrollView.bounds = CGRect(origin: .zero, size: contentSize)
        scrollView.frame = CGRect(origin: originalFrame.origin, size: contentSize)
        scrollView.layoutIfNeeded()

        defer {
            scrollView.bounds = originalBounds
            scrollView.frame = originalFrame
            scrollView.contentOffset = originalOffset
            scrollView.showsVerticalScrollIndicator = originalShowsVertical
            scrollView.showsHorizontalScrollIndicator = originalShowsHorizontal
            scrollView.layoutIfNeeded()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = scrollView.isOpaque

        let renderer = UIGraphicsImageRenderer(size: contentSize, format: format)
        return renderer.image { context in
            scrollView.layer.render(in: context.cgContext)
        }
    }

    private static func captureVisibleWindow(_ keyWindow: UIWindow) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: keyWindow.bounds, format: format)

        let image = renderer.image { rendererContext in
            if !keyWindow.drawHierarchy(in: keyWindow.bounds, afterScreenUpdates: true) {
                keyWindow.layer.render(in: rendererContext.cgContext)
            }
        }
        return image
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
