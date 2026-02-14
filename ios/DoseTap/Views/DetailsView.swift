import SwiftUI
import DoseCore
import HealthKit
import os.log

// MARK: - Timeline Mode
enum TimelineMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case review = "Review"

    var id: String { rawValue }
}

// MARK: - Alarm Ringing View
struct AlarmRingingView: View {
    @ObservedObject private var alarmService = AlarmService.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.red.opacity(0.9), .orange.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                Text("Wake Alarm")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("It is time to wake up and complete your morning check-in.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 24)
                Button {
                    alarmService.stopRinging(acknowledge: true)
                } label: {
                    Text("Stop Alarm")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Details View (Second Tab)
struct DetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject var settings = UserSettingsManager.shared
    @State private var selectedMode: TimelineMode = .live
    @State private var showLiveEventsSheet = false
    @State private var showPlanForTonight = false
    @State private var reviewSessions: [SessionSummary] = []
    @State private var selectedReviewSessionKey: String?
    @State private var reviewEvents: [StoredSleepEvent] = []
    @State private var reviewNightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var reviewShareImage: UIImage?
    @State private var showReviewShareSheet = false
    @State private var isPreparingReviewShare = false
    @State private var reviewShareErrorMessage: String?
    
    // Use customized QuickLog buttons from settings
    private var quickLogEventTypes: [(name: String, icon: String, color: Color)] {
        settings.quickLogButtons.map { ($0.name, $0.icon, $0.color) }
    }

    private var reviewSession: SessionSummary? {
        guard let selectedReviewSessionKey else {
            return reviewSessions.first
        }
        return reviewSessions.first(where: { $0.sessionDate == selectedReviewSessionKey }) ?? reviewSessions.first
    }

    private var selectedReviewIndex: Int? {
        guard let selectedReviewSessionKey else { return nil }
        return reviewSessions.firstIndex(where: { $0.sessionDate == selectedReviewSessionKey })
    }

    private var canGoToOlderReviewNight: Bool {
        guard let index = selectedReviewIndex else { return false }
        return index < (reviewSessions.count - 1)
    }

    private var canGoToNewerReviewNight: Bool {
        guard let index = selectedReviewIndex else { return false }
        return index > 0
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                if selectedMode == .review {
                    VStack(spacing: 20) {
                        Picker("Timeline Mode", selection: $selectedMode) {
                            ForEach(TimelineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        reviewContent
                    }
                    .padding()
                    .padding(.bottom, 80)
                } else {
                    VStack(spacing: 20) {
                        Picker("Timeline Mode", selection: $selectedMode) {
                            ForEach(TimelineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        liveContent
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedMode == .review, reviewSession != nil {
                        Button {
                            shareReviewSnapshot()
                        } label: {
                            if isPreparingReviewShare {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(isPreparingReviewShare)
                        .accessibilityLabel("Share review screenshot")
                    }
                }
            }
            .onAppear {
                refreshReviewContext()
                selectedMode = defaultMode()
            }
            .onReceive(sessionRepo.sessionDidChange) { _ in
                refreshReviewContext()
                if selectedMode == .review, reviewSession == nil {
                    selectedMode = .live
                }
            }
            .sheet(isPresented: $showLiveEventsSheet) {
                TonightEventsSheet(events: eventLogger.events, onDelete: { id in
                    eventLogger.deleteEvent(id: id)
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReviewShareSheet) {
                if let reviewShareImage {
                    ActivityViewController(activityItems: [reviewShareImage])
                }
            }
            .alert("Unable to Share Review", isPresented: Binding(
                get: { reviewShareErrorMessage != nil },
                set: { if !$0 { reviewShareErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    reviewShareErrorMessage = nil
                }
            } message: {
                Text(reviewShareErrorMessage ?? "Unknown error.")
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        LiveNextActionCard(core: core)

        TonightTimelineProgressCard(core: core, events: eventLogger.events)

        FullEventLogGrid(
            eventTypes: quickLogEventTypes,
            eventLogger: eventLogger,
            settings: settings
        )

        LiveEventsPreviewCard(
            events: eventLogger.events,
            onViewAll: { showLiveEventsSheet = true }
        )
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let session = reviewSession {
            VStack(spacing: 20) {
                ReviewStickyHeaderBar(
                    session: session,
                    events: reviewEvents,
                    nightDate: reviewNightDate,
                    hasMorningCheckIn: sessionRepo.fetchMorningCheckIn(for: session.sessionDate) != nil,
                    canGoToOlderNight: canGoToOlderReviewNight,
                    canGoToNewerNight: canGoToNewerReviewNight,
                    nightPositionText: reviewNightPositionText,
                    onGoOlder: goToOlderReviewNight,
                    onGoNewer: goToNewerReviewNight
                )

                CoachSummaryCard(
                    session: session,
                    events: reviewEvents
                )

                MergedNightTimelineCard(
                    session: session,
                    events: reviewEvents,
                    nightDate: reviewNightDate,
                    fullViewDestination: AnyView(
                        TimelineReviewDetailView(
                            core: core,
                            initialSessionKey: session.sessionDate
                        )
                    ),
                    fullViewLabel: "Full view"
                )

                ReviewKeyMetricsCard(session: session, events: reviewEvents)

                ReviewEventsAndNotesCard(
                    events: reviewEvents,
                    onKeepEvent: { event, group in
                        keepDuplicateEvent(event, in: group)
                    },
                    onDeleteEvent: { event in
                        deleteDuplicateEvent(event)
                    },
                    onMergeGroup: { group in
                        mergeDuplicateEvents(in: group)
                    }
                )

                DisclosureGroup(isExpanded: $showPlanForTonight) {
                    FullSessionDetails(core: core)
                        .padding(.top, 10)
                } label: {
                    Text("Plan for Tonight")
                        .font(.headline)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No completed night to review yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Switch to Live mode to track tonight's session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }

    private func refreshReviewContext() {
        let fetchedSessions = sessionRepo.fetchRecentSessions(days: 120)
        var sessionByKey: [String: SessionSummary] = [:]
        for session in fetchedSessions {
            sessionByKey[session.sessionDate] = session
        }

        let calendar = Calendar.current
        let candidates: [SessionSummary] = (1...90).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                return nil
            }
            let key = sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
            return sessionByKey[key] ?? SessionSummary(sessionDate: key)
        }

        reviewSessions = candidates
        if let key = selectedReviewSessionKey, candidates.contains(where: { $0.sessionDate == key }) {
            selectedReviewSessionKey = key
        } else {
            selectedReviewSessionKey = candidates.first?.sessionDate
        }
        loadSelectedReviewSessionData()
    }

    private func loadSelectedReviewSessionData() {
        guard let selected = reviewSession else {
            reviewEvents = []
            reviewNightDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return
        }

        reviewEvents = sessionRepo.fetchSleepEvents(for: selected.sessionDate).sorted(by: { $0.timestamp < $1.timestamp })
        reviewNightDate = Self.sessionDateFormatter.date(from: selected.sessionDate)
            ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())
            ?? Date()
    }

    private func defaultMode() -> TimelineMode {
        if core.currentStatus == .completed || core.currentStatus == .finalizing || core.currentStatus == .closed {
            return .review
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if (7...15).contains(hour), reviewSession != nil, core.dose1Time == nil {
            return .review
        }
        return .live
    }

    private func keepDuplicateEvent(_ keep: StoredSleepEvent, in group: StoredEventDuplicateGroup) {
        for event in group.events where event.id != keep.id {
            sessionRepo.deleteSleepEvent(id: event.id)
        }
        refreshReviewContext()
    }

    private func deleteDuplicateEvent(_ event: StoredSleepEvent) {
        sessionRepo.deleteSleepEvent(id: event.id)
        refreshReviewContext()
    }

    private func mergeDuplicateEvents(in group: StoredEventDuplicateGroup) {
        guard let canonical = group.events.sorted(by: { $0.timestamp < $1.timestamp }).first else {
            return
        }
        keepDuplicateEvent(canonical, in: group)
    }

    private var reviewNightPositionText: String {
        guard let index = selectedReviewIndex else { return "" }
        return "\(index + 1) of \(reviewSessions.count)"
    }

    private func goToOlderReviewNight() {
        guard let index = selectedReviewIndex, canGoToOlderReviewNight else { return }
        selectedReviewSessionKey = reviewSessions[index + 1].sessionDate
        loadSelectedReviewSessionData()
    }

    private func goToNewerReviewNight() {
        guard let index = selectedReviewIndex, canGoToNewerReviewNight else { return }
        selectedReviewSessionKey = reviewSessions[index - 1].sessionDate
        loadSelectedReviewSessionData()
    }

    private func shareReviewSnapshot() {
        guard let session = reviewSession else { return }
        isPreparingReviewShare = true
        reviewShareErrorMessage = nil

        Task { @MainActor in
            let snapshotTimeline = await fetchSnapshotSleepTimeline(for: reviewNightDate)
            InsightsCalculator.shared.computeInsights()

            let content = TimelineReviewShareSnapshotView(
                session: session,
                events: reviewEvents,
                nightDate: reviewNightDate,
                hasMorningCheckIn: sessionRepo.fetchMorningCheckIn(for: session.sessionDate) != nil,
                core: core,
                snapshotTimeline: snapshotTimeline
            )
            .frame(width: UIScreen.main.bounds.width - 24)
            .padding(.vertical, 8)
            .environment(\.colorScheme, colorScheme)
            .preferredColorScheme(colorScheme)

            let renderer = ImageRenderer(content: content)
            renderer.scale = UIScreen.main.scale

            if let image = renderer.uiImage {
                reviewShareImage = image
                showReviewShareSheet = true
            } else {
                reviewShareErrorMessage = "Could not generate a screenshot for this review."
            }

            isPreparingReviewShare = false
        }
    }

    private func fetchSnapshotSleepTimeline(for nightDate: Date) async -> ReviewSnapshotSleepTimeline? {
        let healthKit = HealthKitService.shared
        guard UserSettingsManager.shared.healthKitEnabled else { return nil }
        healthKit.checkAuthorizationStatus()
        guard healthKit.isAuthorized else { return nil }

        let queryStart = eveningAnchorDate(for: nightDate, hour: 18)
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else { return nil }
        let queryEnd = eveningAnchorDate(for: nextDay, hour: 12)

        do {
            let segments = try await healthKit.fetchSegmentsForTimeline(from: queryStart, to: queryEnd)
            let stages = segments
                .map { segment in
                    SleepStageBand(
                        stage: mapHealthStageToTimeline(segment.stage),
                        startTime: segment.start,
                        endTime: segment.end
                    )
                }
                .sorted(by: { $0.startTime < $1.startTime })
            let filteredStages = primaryNightSleepBands(from: stages)

            guard !filteredStages.isEmpty else { return nil }

            let start = filteredStages.map(\.startTime).min() ?? queryStart
            let end = filteredStages.map(\.endTime).max() ?? queryEnd
            return ReviewSnapshotSleepTimeline(stages: filteredStages, start: start, end: end)
        } catch {
            return nil
        }
    }

    private func mapHealthStageToTimeline(_ stage: HealthKitService.SleepStage) -> SleepStage {
        switch HealthKitService.mapToDisplayStage(stage) {
        case .awake:
            return .awake
        case .light, .core:
            return .light
        case .deep:
            return .deep
        case .rem:
            return .rem
        }
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}
