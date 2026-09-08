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
    @State private var section = "All"
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
                    Text("All").tag("All")
                    Text("Overview").tag("Overview")
                    Text("Trends").tag("Trends")
                    Text("Data").tag("Data")
                }.pickerStyle(.segmented).padding(.horizontal)
                    .accessibilityIdentifier("dashboard-section-picker")

                DisclosureGroup("Dashboard colors & missing data") {
                    Text("Blue values: dose timing. Purple: sleep and check-ins. Teal: record coverage. Gray: context or no data. Orange review flags need a record check. Chart legends identify their series; WHOOP recovery uses its labeled ranges. Color alone is not a health rating.")
                        .font(.caption).foregroundColor(.secondary)
                }.font(.callout).padding(.horizontal).padding(.top, 8)

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
                    if !model.populatedNights.isEmpty {
                        if section == "All" || section == "Overview" {
                            dashboardHeading("Overview")
                            DashboardExecutiveSummaryCard(model: model, core: core)
                            DashboardDosingSnapshotCard(model: model)
                            DashboardSleepSnapshotCard(model: model)
                            if !model.whoopNights.isEmpty {
                                DashboardWHOOPCard(model: model)
                            } else {
                                unavailableCard("WHOOP Recovery & Biometrics", detail: "No WHOOP nights in this range. Check the WHOOP connection in Settings, then refresh or choose a wider range.")
                            }
                        }
                        if section == "All" || section == "Trends" {
                            dashboardHeading("Trends")
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Sleep source for comparisons", selection: $model.sleepSource) {
                                    ForEach(DashboardSleepSource.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text("\(model.sleepSampleCount) nights from \(model.sleepSource.rawValue). Missing readings are excluded; sources are never substituted.")
                                    .font(.caption).foregroundColor(.secondary)
                            }.gridCellColumns(columns.count)
                            if !model.periodComparison.isEmpty {
                                DashboardPeriodComparisonCard(model: model)
                            } else {
                                unavailableCard("Period Comparison", detail: "A comparison needs matching measurements in this range and the preceding period. All Time has no preceding comparison period.")
                            }
                            DashboardTrendChartsCard(model: model).gridCellColumns(columns.count)
                            DashboardWakeComparisonCard(model: model).gridCellColumns(columns.count)
                            DashboardFoodDiaryCard(model: model).gridCellColumns(columns.count)
                            DashboardLifestyleFactorsCard(model: model)
                            DashboardMoodSymptomsCard(model: model)
                            DashboardStressTrendsCard(model: model).gridCellColumns(columns.count)
                        }
                    }
                    if section == "All" || section == "Data" {
                        dashboardHeading("Data")
                        DashboardDataQualityCard(model: model)
                        DashboardIntegrationsCard(states: model.integrationStates)
                        DashboardRecentNightsCard(nights: model.trendNights, onResolveDuplicateGroup: { resolvingDuplicateGroup = $0 })
                            .gridCellColumns(columns.count)
                        DashboardCapturedMetricsCard(categories: model.metricsCatalog)
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

    private func dashboardHeading(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .gridCellColumns(columns.count)
    }

    private func unavailableCard(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

}
