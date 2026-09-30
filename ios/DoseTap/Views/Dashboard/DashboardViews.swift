import SwiftUI
import DoseCore
#if canImport(UIKit)
import UIKit
#endif

struct DashboardTabView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isInSplitView) private var isInSplitView
    @StateObject private var model = DashboardAnalyticsModel()
    @StateObject private var cloudSync = DeferredCloudKitSyncService.shared
    @State private var resolvingDuplicateGroup: StoredEventDuplicateGroup?
    @State private var page: DashboardPage = .timing
    @State private var showingInspection = false
    @State private var cloudSyncError: String?

    private var palette: DashboardPalette { DashboardPalette(isNight: themeManager.currentTheme == .night) }

    var body: some View {
        Group {
            if isInSplitView {
                dashboardContent
            } else {
                NavigationStack { dashboardContent }
            }
        }.environment(\.dashboardPalette, palette)
    }

    private var selectedPage: Binding<DashboardPage> {
        Binding(get: { page }, set: { newPage in
            if let mode = newPage.replayMode { model.replayPresentation.mode = mode }
            page = newPage
        })
    }
    private var rangePicker: some View {
        DashboardPeriodControls(model: model)
    }

    private var dashboardContent: some View {
            VStack(spacing: 8) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                        VStack(spacing: 0) { rangePicker; DashboardPagePicker(selection: selectedPage) }
                    } else {
                        HStack { rangePicker; DashboardPagePicker(selection: selectedPage) }
                    }
                }.padding(.horizontal)
                if dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                    DisclosureGroup("Reporting period details") {
                        Text(model.rangeDescription).multilineTextAlignment(.leading)
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Text(model.rangeDescription).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(.horizontal)
                }
                if page.requiresNightEvidence && !model.isLoading && model.populatedNights.isEmpty {
                    VStack(spacing: 4) {
                        Text("No session or provider observations in this range").font(.headline)
                        Text("Choose a wider range, record a night from Tonight, or Refresh connected sleep sources. Independent daytime and nap records remain available in their views.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.center).padding(.horizontal)
                        .accessibilityIdentifier("dashboard-empty-nights")
                }
                dashboardPageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(isInSplitView ? .automatic : .inline)
            .toolbar(.visible, for: .navigationBar)
            .refreshable {
                await model.refreshAndWait()
            }
            .toolbar {
                PageToolbar {
                    Button { showingInspection = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }.accessibilityLabel("Dashboard shared filters")
                        .accessibilityIdentifier("dashboard-shared-filters")
                    if cloudSync.cloudSyncAvailableInBuild {
                        if cloudSync.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task {
                                    do {
                                        try await cloudSync.syncNow(days: 120)
                                        model.refresh()
                                    } catch {
                                        cloudSyncError = error.localizedDescription
                                    }
                                }
                            } label: {
                                Image(systemName: "icloud.and.arrow.up")
                            }
                            .accessibilityLabel("Sync with iCloud")
                        }
                    }
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            model.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh dashboard")
                    }
                }
            }
            .overlay {
                if model.isLoading && model.nights.isEmpty {
                    ProgressView("Building dashboard…")
                }
            }
            .task {
                model.refresh()
            }
            .onChange(of: model.replayPresentation.mode) { mode in
                if page.replayMode != nil { page = DashboardPage.page(for: mode) }
            }
            .onChange(of: model.selectedRange) { _ in model.refresh() }
            .onReceive(sessionRepo.sessionDidChange) { _ in
                model.refresh()
            }
            .sheet(isPresented: $showingInspection) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(model.rangeDescription).font(.caption)
                            DashboardInspectionControls(model: model)
                        }.padding()
                    }
                        .navigationTitle("Dashboard filters")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInspection = false } } }
                }
            }
            .sheet(item: $resolvingDuplicateGroup) { group in
                DuplicateResolutionSheet(
                    group: group,
                    onKeepEvent: { keep in
                        for event in group.events where event.id != keep.id {
                            sessionRepo.deleteSleepEvent(id: event.id)
                        }
                        model.refresh()
                    },
                    onDeleteEvent: { event in
                        sessionRepo.deleteSleepEvent(id: event.id)
                        model.refresh()
                    },
                    onMergeGroup: {
                        if let canonical = group.events.sorted(by: { $0.timestamp < $1.timestamp }).first {
                            for event in group.events where event.id != canonical.id {
                                sessionRepo.deleteSleepEvent(id: event.id)
                            }
                            model.refresh()
                        }
                    }
                )
            }
            .alert("Cloud Sync", isPresented: Binding(
                get: { cloudSyncError != nil },
                set: { if !$0 { cloudSyncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cloudSyncError ?? "Unknown cloud sync error")
            }
    }

    @ViewBuilder private var dashboardPageContent: some View {
        switch page {
        case .timing, .intervals, .opportunity, .medications, .coverage:
            DashboardReplayView(model: model)
        case .sleepNaps: SleepNapsDashboardView(model: model)
        case .dosePatterns: ScrollView { DosePatternDashboardView(model: model).padding() }
        case .work: DashboardWorkBlockView(model: model)
        case .context: ContextMorningOutcomesView(model: model)
        case .daytime: DashboardDaytimeRoute(model: model)
        case .physician: ScrollView { PhysicianDashboardReviewLink(model: model).padding() }
        case .data: reviewData
        case .additional: DashboardAdditionalMeasuresView(model: model, core: core)
        }
    }

    private var reviewData: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What records are available for review?").font(.title2.bold())
                Text("This inventory covers the whole selected reporting range. Night-level comparison filters do not remove records from this inventory.")
                    .font(.callout).foregroundStyle(.secondary)
                DashboardDataQualityCard(model: model)
                DashboardIntegrationsCard(states: model.integrationStates)
                NavigationLink("Review provider-to-session matches") { ProviderSessionAssociationView(model: model) }
                    .accessibilityIdentifier("dashboard-provider-match-open")
                DisclosureGroup("Storage & iPad access") {
                    Text(cloudSync.cloudSyncAvailableInBuild
                        ? "This validation build has experimental cloud sync. Complete cross-device record coverage and conflict handling remain under review."
                        : "DoseTap records are stored locally. Automatic DoseTap iCloud sync is disabled. Use the explicit nearby transfer in Settings to update an iPad review snapshot.")
                    Text("Apple Health syncing, device backups, and files saved to iCloud Drive are separate. An exported file is a review snapshot, not a live dashboard or full-app restore.")
                }
                DisclosureGroup("Colors & missing data") { Text(palette.legend) }
                DashboardRecentNightsCard(nights: model.trendNights, onResolveDuplicateGroup: { resolvingDuplicateGroup = $0 })
                DashboardCapturedMetricsCard(categories: model.metricsCatalog)
            }.padding().padding(.bottom, 90)
        }.accessibilityIdentifier("dashboard-data-review")
    }
}
