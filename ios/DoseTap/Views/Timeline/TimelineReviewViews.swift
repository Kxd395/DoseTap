import SwiftUI
import DoseCore

struct TimelineReviewDetailView: View {
    @ObservedObject var core: DoseTapCore
    let initialSessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var reviewSessions: [SessionSummary] = []
    @State private var selectedReviewSessionKey: String?
    @State private var reviewEvents: [StoredSleepEvent] = []
    @State private var reviewNightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var showPlanForTonight = false

    init(core: DoseTapCore, initialSessionKey: String) {
        self.core = core
        self.initialSessionKey = initialSessionKey
        _selectedReviewSessionKey = State(initialValue: initialSessionKey)
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

    private var reviewNightPositionText: String {
        guard let index = selectedReviewIndex else { return "" }
        return "\(index + 1) of \(reviewSessions.count)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let session = reviewSession {
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

                    DoseTimingCard(sessionKey: session.sessionDate)

                    NightScoreCard(sessionKey: session.sessionDate)

                    ReviewKeyMetricsCard(session: session, events: reviewEvents)

                    PreSleepLogCard(sessionKey: session.sessionDate)

                    MorningCheckInCard(sessionKey: session.sessionDate)

                    MergedNightTimelineCard(
                        session: session,
                        events: reviewEvents,
                        nightDate: reviewNightDate,
                        showFullViewLink: false
                    )

                    HealthDataCard(sessionKey: session.sessionDate)

                    InsightsSummaryCard(title: "Last 14-Night Trends", showDefinitions: true)

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

                    ExportCard(sessionKey: session.sessionDate)

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
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.zzz")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No completed night to review yet")
                            .font(.subheadline)
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
            .padding()
            .padding(.bottom, 24)
        }
        .navigationTitle("Full Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .onAppear {
            refreshReviewContext()
        }
        .onReceive(sessionRepo.sessionDidChange) { _ in
            refreshReviewContext()
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
        } else if candidates.contains(where: { $0.sessionDate == initialSessionKey }) {
            selectedReviewSessionKey = initialSessionKey
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
        reviewNightDate = AppFormatters.sessionDate.date(from: selected.sessionDate)
            ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())
            ?? Date()
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
}
