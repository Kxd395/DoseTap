import SwiftUI
import DoseCore
#if canImport(UIKit)
import UIKit
#endif

struct DashboardTabView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isInSplitView) private var isInSplitView
    @StateObject private var model = DashboardAnalyticsModel()
    @StateObject private var cloudSync = DeferredCloudKitSyncService.shared
    @State private var resolvingDuplicateGroup: StoredEventDuplicateGroup?
    @State private var cloudSyncError: String?

    private var isWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var columns: [GridItem] {
        isWideLayout
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible())]
    }

    var body: some View {
        if isInSplitView {
            dashboardContent
        } else {
            NavigationView {
                dashboardContent
            }
        }
    }

    private var dashboardContent: some View {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Date Range Picker
                    Picker("Range", selection: $model.selectedRange) {
                        ForEach(DashboardDateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Text(model.selectedRange.label + " • \(model.populatedNights.count) nights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    DashboardExecutiveSummaryCard(model: model, core: core)
                        .gridCellColumns(columns.count)

                    // Period comparison (if prior data exists)
                    if !model.periodComparison.isEmpty {
                        DashboardPeriodComparisonCard(model: model)
                            .gridCellColumns(columns.count)
                    }

                    DashboardDosingSnapshotCard(model: model)
                    DashboardSleepSnapshotCard(model: model)

                    // WHOOP Recovery & Biometrics (only when data exists)
                    if !model.whoopNights.isEmpty {
                        DashboardWHOOPCard(model: model)
                            .gridCellColumns(columns.count)
                    }

                    // Dose Effectiveness Analysis (when enough data)
                    if model.doseEffectivenessReport.totalNights >= 3 {
                        DashboardDoseEffectivenessCard(report: model.doseEffectivenessReport)
                            .gridCellColumns(columns.count)
                    }

                    DashboardLifestyleFactorsCard(model: model)
                    DashboardMoodSymptomsCard(model: model)
                    DashboardStressTrendsCard(model: model)
                        .gridCellColumns(columns.count)

                    DashboardDataQualityCard(model: model)
                    DashboardIntegrationsCard(states: model.integrationStates)

                    DashboardTrendChartsCard(model: model)
                        .gridCellColumns(columns.count)

                    DashboardRecentNightsCard(
                        nights: model.trendNights,
                        onResolveDuplicateGroup: { group in
                            resolvingDuplicateGroup = group
                        }
                    )
                        .gridCellColumns(columns.count)

                    DashboardCapturedMetricsCard(categories: model.metricsCatalog)
                        .gridCellColumns(columns.count)
                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("Dashboard")
            .refreshable {
                model.refresh()
            }
            .toolbar {
                if cloudSync.cloudSyncAvailableInBuild {
                    ToolbarItem(placement: .navigationBarTrailing) {
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
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
            .onReceive(sessionRepo.sessionDidChange) { _ in
                model.refresh()
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
}
