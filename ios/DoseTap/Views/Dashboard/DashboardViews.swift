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
    @State private var section = "Overview"
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
            NavigationStack {
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

                    Text(model.selectedRange.label + " • \(model.populatedNights.count) nights with data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Picker("Dashboard section", selection: $section) {
                    Text("Overview").tag("Overview")
                    Text("Trends").tag("Trends")
                    Text("Data").tag("Data")
                }.pickerStyle(.segmented).padding(.horizontal)

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundColor(.orange).padding()
                }
                if !model.isLoading && model.populatedNights.isEmpty {
                    VStack(spacing: 8) {
                        Text("No data in this range").font(.headline)
                        Text("Choose a wider range or record a night from Tonight. Connected sleep sources appear after Refresh.")
                            .font(.callout).foregroundColor(.secondary)
                    }.multilineTextAlignment(.center).padding()
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    if section == "Overview" {
                        DashboardExecutiveSummaryCard(model: model, core: core)
                        DashboardDosingSnapshotCard(model: model)
                        DashboardSleepSnapshotCard(model: model)
                        if !model.whoopNights.isEmpty { DashboardWHOOPCard(model: model) }
                    } else if section == "Trends" {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Sleep source for comparisons", selection: $model.sleepSource) {
                                ForEach(DashboardSleepSource.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                            Text("\(model.sleepSampleCount) nights from \(model.sleepSource.rawValue). Missing readings are excluded; sources are never substituted.")
                                .font(.caption).foregroundColor(.secondary)
                        }.gridCellColumns(columns.count)
                        if !model.periodComparison.isEmpty { DashboardPeriodComparisonCard(model: model) }
                        DashboardTrendChartsCard(model: model).gridCellColumns(columns.count)
                        if model.doseEffectivenessReport.totalNights >= 3 {
                            DashboardDoseEffectivenessCard(report: model.doseEffectivenessReport)
                        }
                        DashboardLifestyleFactorsCard(model: model)
                        DashboardMoodSymptomsCard(model: model)
                        DashboardStressTrendsCard(model: model).gridCellColumns(columns.count)
                    } else {
                        DashboardDataQualityCard(model: model)
                        DashboardIntegrationsCard(states: model.integrationStates)
                        DashboardRecentNightsCard(nights: model.trendNights, onResolveDuplicateGroup: { resolvingDuplicateGroup = $0 })
                            .gridCellColumns(columns.count)
                    }
                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await model.refreshAndWait()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PageCaptureButton() }
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
