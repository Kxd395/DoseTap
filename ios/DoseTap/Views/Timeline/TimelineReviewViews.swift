import SwiftUI
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

struct LiveNextActionCard: View {
    @ObservedObject var core: DoseTapCore

    private var headline: String {
        switch core.currentStatus {
        case .noDose1:
            return "Next Action: Take Dose 1"
        case .beforeWindow:
            return "Next Action: Wait for Dose 2 Window"
        case .active, .nearClose:
            return "Next Action: Take Dose 2"
        case .closed:
            return "Dose 2 Window Closed"
        case .completed, .finalizing:
            return "Session Complete"
        }
    }

    private var detail: String {
        guard let dose1 = core.dose1Time else {
            return "Start tonight's session to unlock timeline guidance."
        }
        let windowOpen = dose1.addingTimeInterval(150 * 60)
        let windowClose = dose1.addingTimeInterval(240 * 60)
        switch core.currentStatus {
        case .beforeWindow:
            return "Dose 2 window opens at \(windowOpen.formatted(date: .omitted, time: .shortened))."
        case .active, .nearClose:
            return "Sleep window: \(windowOpen.formatted(date: .omitted, time: .shortened)) - \(windowClose.formatted(date: .omitted, time: .shortened))."
        case .closed:
            return "Window closed at \(windowClose.formatted(date: .omitted, time: .shortened))."
        case .completed, .finalizing:
            return "Review last night for tonight's adjustments."
        case .noDose1:
            return "Take Dose 1 when you're ready to begin."
        }
    }

    private var accent: Color {
        switch core.currentStatus {
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .red
        case .completed, .finalizing: return .blue
        default: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.headline)
                .foregroundColor(accent)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(0.12))
        )
    }
}

struct LiveTimelineItem: Identifiable {
    let id: String
    let title: String
    let time: Date
    let color: Color
    let isUpcoming: Bool
}

struct TonightTimelineProgressCard: View {
    @ObservedObject var core: DoseTapCore
    let events: [LoggedEvent]

    private var items: [LiveTimelineItem] {
        var markers: [LiveTimelineItem] = []

        if let dose1 = core.dose1Time {
            markers.append(LiveTimelineItem(
                id: "dose1",
                title: "Dose 1",
                time: dose1,
                color: .blue,
                isUpcoming: false
            ))

            let windowOpen = dose1.addingTimeInterval(150 * 60)
            let windowClose = dose1.addingTimeInterval(240 * 60)
            markers.append(LiveTimelineItem(
                id: "window_open",
                title: "Window Opens",
                time: windowOpen,
                color: .orange,
                isUpcoming: windowOpen > Date()
            ))
            markers.append(LiveTimelineItem(
                id: "window_close",
                title: "Window Closes",
                time: windowClose,
                color: .red,
                isUpcoming: windowClose > Date()
            ))
        }

        if let dose2 = core.dose2Time {
            markers.append(LiveTimelineItem(
                id: "dose2",
                title: "Dose 2",
                time: dose2,
                color: .green,
                isUpcoming: false
            ))
        }

        for event in events {
            markers.append(LiveTimelineItem(
                id: event.id.uuidString,
                title: EventDisplayName.displayName(for: event.name),
                time: event.time,
                color: event.color,
                isUpcoming: false
            ))
        }

        return markers.sorted(by: { $0.time < $1.time })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tonight Timeline (So Far)")
                .font(.headline)

            if items.isEmpty {
                Text("No timeline events yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color.opacity(item.isUpcoming ? 0.45 : 1))
                            .frame(width: 10, height: 10)
                        Text(item.title)
                            .font(.subheadline)
                        Spacer()
                        Text(item.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if item.isUpcoming {
                            Text("Up next")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct LiveEventsPreviewCard: View {
    let events: [LoggedEvent]
    let onViewAll: () -> Void

    private var duplicateGroups: [LoggedEventDuplicateGroup] {
        buildLoggedEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tonight's Events")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    onViewAll()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Possible duplicate: \(group.displayName) (\(group.events.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(events.sorted(by: { $0.time > $1.time }).prefix(6)) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        Text(EventDisplayName.displayName(for: event.name))
                            .font(.subheadline)
                        Spacer()
                        Text(event.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct ReviewHeaderCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"

        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        if session.dose1Time == nil, session.dose2Time == nil, events.isEmpty {
            return "No manual logs for this night"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.headline)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct ReviewStickyHeaderBar: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool
    let canGoToOlderNight: Bool
    let canGoToNewerNight: Bool
    let nightPositionText: String
    let onGoOlder: () -> Void
    let onGoNewer: () -> Void

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"
        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        if session.dose1Time == nil, session.dose2Time == nil, events.isEmpty {
            return "No manual logs for this night"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onGoOlder) {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToOlderNight)
                .opacity(canGoToOlderNight ? 1 : 0.35)
                .accessibilityLabel("Older night")

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text((canGoToOlderNight || canGoToNewerNight) ? nightPositionText : "Only night")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))

                Button(action: onGoNewer) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNewerNight)
                .opacity(canGoToNewerNight ? 1 : 0.35)
                .accessibilityLabel("Newer night")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct CoachSummaryCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]

    private var hasAnySessionData: Bool {
        session.dose1Time != nil || session.dose2Time != nil || !events.isEmpty
    }

    private var doseWindow: (open: Date, close: Date)? {
        guard let dose1 = session.dose1Time else { return nil }
        return (dose1.addingTimeInterval(150 * 60), dose1.addingTimeInterval(240 * 60))
    }

    private var lightsOutTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "lights_out" }
            .map(\.timestamp)
            .min()
    }

    private var totalInBedText: String {
        guard
            let lightsOut = lightsOutTime,
            let wake = events
                .filter({ normalizeStoredEventType($0.eventType) == "wake_final" })
                .map(\.timestamp)
                .max()
        else {
            if !hasAnySessionData {
                return "No session data recorded."
            }
            return session.intervalMinutes.map { "Dose interval was \(TimeIntervalMath.formatMinutes($0))." }
                ?? "Session data captured."
        }
        return "Top outcome: \(TimeIntervalMath.formatMinutes(TimeIntervalMath.minutesBetween(start: lightsOut, end: wake))) in bed."
    }

    private var frictionText: String {
        let disruptions = events.filter {
            let normalized = normalizeStoredEventType($0.eventType)
            return normalized == "bathroom" || normalized == "wake_temp" || normalized == "noise" || normalized == "pain"
        }
        if !hasAnySessionData {
            return "Biggest friction: insufficient data logged."
        }
        if disruptions.isEmpty {
            return "Biggest friction: no major disruptions logged."
        }
        return "Biggest friction: \(disruptions.count) overnight disruptions logged."
    }

    private var actions: [String] {
        var suggestions: [String] = []

        if !hasAnySessionData {
            return ["Log lights out, final wake, and only meaningful overnight disruptions tonight."]
        }

        if let window = doseWindow, let lightsOut = lightsOutTime {
            if lightsOut < window.open || lightsOut > window.close {
                suggestions.append("Aim lights-out inside the window (\(window.open.formatted(date: .omitted, time: .shortened))-\(window.close.formatted(date: .omitted, time: .shortened))).")
            }
        }

        if let interval = session.intervalMinutes, !(150...240).contains(interval) {
            suggestions.append("Move Dose 2 toward the 150-240 minute window after Dose 1.")
        }

        let duplicates = buildStoredEventDuplicateGroups(events: events)
        if !duplicates.isEmpty {
            suggestions.append("Resolve duplicate event logs before relying on trend metrics.")
        }

        if suggestions.isEmpty {
            suggestions.append("Keep timing consistent tonight and log only meaningful wake events.")
        }

        return Array(suggestions.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Summary")
                .font(.headline)
            Text(totalInBedText)
                .font(.subheadline)
            Text(frictionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            Text("Tonight's focus")
                .font(.subheadline.bold())
            ForEach(actions, id: \.self) { action in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(action)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct MergedNightTimelineItem: Identifiable {
    let id: String
    let title: String
    let time: Date
    let color: Color
}

struct MergedNightTimelineCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    var showFullViewLink: Bool = true
    var fullViewDestination: AnyView?
    var fullViewLabel: String = "Full view"
    var snapshotTimeline: ReviewSnapshotSleepTimeline?
    var allowLiveTimelineFallback: Bool = true

    private var mergedItems: [MergedNightTimelineItem] {
        var rows: [MergedNightTimelineItem] = []

        if let dose1 = session.dose1Time {
            rows.append(MergedNightTimelineItem(id: "dose1", title: "Dose 1", time: dose1, color: .blue))
            rows.append(MergedNightTimelineItem(id: "window_open", title: "Window Opens", time: dose1.addingTimeInterval(150 * 60), color: .orange))
            rows.append(MergedNightTimelineItem(id: "window_close", title: "Window Closes", time: dose1.addingTimeInterval(240 * 60), color: .red))
        }
        if let dose2 = session.dose2Time {
            rows.append(MergedNightTimelineItem(id: "dose2", title: "Dose 2", time: dose2, color: .green))
        }

        for event in events {
            rows.append(
                MergedNightTimelineItem(
                    id: event.id,
                    title: EventDisplayName.displayName(for: event.eventType),
                    time: event.timestamp,
                    color: Color(hex: event.colorHex ?? "#888888") ?? .gray
                )
            )
        }

        return rows.sorted(by: { $0.time < $1.time })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Night Timeline (Merged)")
                    .font(.headline)
                Spacer()
                if showFullViewLink {
                    NavigationLink(
                        destination: fullViewDestination ?? AnyView(SleepTimelineContainer())
                    ) {
                        Text(fullViewLabel)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            if let snapshotTimeline {
                SleepStageTimeline(
                    stages: snapshotTimeline.stages,
                    events: [],
                    startTime: snapshotTimeline.start,
                    endTime: snapshotTimeline.end
                )
                StageSummaryCard(stages: snapshotTimeline.stages)
            } else if allowLiveTimelineFallback {
                LiveSleepTimelineView(nightDate: nightDate)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Sleep timeline unavailable for this export.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            if !mergedItems.isEmpty {
                Divider()
                ForEach(mergedItems) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.title)
                            .font(.caption)
                        Spacer()
                        Text(item.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

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

                    MergedNightTimelineCard(
                        session: session,
                        events: reviewEvents,
                        nightDate: reviewNightDate,
                        showFullViewLink: false
                    )

                    InsightsSummaryCard(title: "Key Metrics", showDefinitions: true)

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
        reviewNightDate = Self.sessionDateFormatter.date(from: selected.sessionDate)
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

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

struct ReviewSnapshotSleepTimeline {
    let stages: [SleepStageBand]
    let start: Date
    let end: Date
}

struct TimelineReviewShareSnapshotView: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool
    @ObservedObject var core: DoseTapCore
    let snapshotTimeline: ReviewSnapshotSleepTimeline?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DoseTap Timeline Review")
                .font(.headline)
            Text("Generated \(Date().formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            ReviewHeaderCard(
                session: session,
                events: events,
                nightDate: nightDate,
                hasMorningCheckIn: hasMorningCheckIn
            )

            CoachSummaryCard(session: session, events: events)

            MergedNightTimelineCard(
                session: session,
                events: events,
                nightDate: nightDate,
                showFullViewLink: false,
                snapshotTimeline: snapshotTimeline,
                allowLiveTimelineFallback: false
            )

            InsightsSummaryCard(title: "Key Metrics", showDefinitions: true)

            ReviewEventsSnapshotCard(events: events)

            VStack(alignment: .leading, spacing: 10) {
                Text("Plan for Tonight")
                    .font(.headline)
                FullSessionDetails(core: core)
                    .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}

struct ReviewEventsSnapshotCard: View {
    let events: [StoredSleepEvent]

    private var duplicateGroups: [StoredEventDuplicateGroup] {
        buildStoredEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events & Notes")
                .font(.headline)

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    Text("Possible duplicate: \(group.displayName) (\(group.events.count))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if events.isEmpty {
                Text("No review events for this night.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20), id: \.id) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(EventDisplayName.displayName(for: event.eventType))
                            .font(.caption)
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct ReviewEventsAndNotesCard: View {
    let events: [StoredSleepEvent]
    let onKeepEvent: (StoredSleepEvent, StoredEventDuplicateGroup) -> Void
    let onDeleteEvent: (StoredSleepEvent) -> Void
    let onMergeGroup: (StoredEventDuplicateGroup) -> Void
    @State private var selectedDuplicateGroup: StoredEventDuplicateGroup?

    private var duplicateGroups: [StoredEventDuplicateGroup] {
        buildStoredEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events & Notes")
                .font(.headline)

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Possible duplicate: \(group.displayName) (\(group.events.count))", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                            Button("Resolve") {
                                selectedDuplicateGroup = group
                            }
                            .font(.caption)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                    )
                }
            }

            if events.isEmpty {
                Text("No review events for this night.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.sorted(by: { $0.timestamp > $1.timestamp }), id: \.id) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(EventDisplayName.displayName(for: event.eventType))
                            .font(.subheadline)
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .sheet(item: $selectedDuplicateGroup) { group in
            DuplicateResolutionSheet(
                group: group,
                onKeepEvent: { event in
                    onKeepEvent(event, group)
                },
                onDeleteEvent: onDeleteEvent,
                onMergeGroup: {
                    onMergeGroup(group)
                }
            )
        }
    }
}

struct DuplicateResolutionSheet: View {
    let group: StoredEventDuplicateGroup
    let onKeepEvent: (StoredSleepEvent) -> Void
    let onDeleteEvent: (StoredSleepEvent) -> Void
    let onMergeGroup: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var sortedEvents: [StoredSleepEvent] {
        group.events.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Resolve these \(group.events.count) \(group.displayName) logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Merge") {
                        onMergeGroup()
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }

                Section("Choose an event") {
                    ForEach(sortedEvents, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.bold())
                                Spacer()
                                if let notes = event.notes, !notes.isEmpty {
                                    Text("Has notes")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Button("Keep this") {
                                    onKeepEvent(event)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Delete") {
                                    onDeleteEvent(event)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Resolve Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LoggedEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [LoggedEvent]
}

struct StoredEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [StoredSleepEvent]
}

func buildLoggedEventDuplicateGroups(events: [LoggedEvent], threshold: TimeInterval = 30 * 60) -> [LoggedEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.time < $1.time })) { normalizeLoggedEventName($0.name) }
    var duplicates: [LoggedEventDuplicateGroup] = []

    for (normalizedName, group) in grouped {
        let clusters = clusterEventsByTime(events: group, threshold: threshold)
        for cluster in clusters where cluster.count > 1 {
            duplicates.append(
                LoggedEventDuplicateGroup(
                    id: "\(normalizedName)-\(cluster.first?.id.uuidString ?? UUID().uuidString)",
                    displayName: EventDisplayName.displayName(for: normalizedName),
                    events: cluster
                )
            )
        }
    }
    return duplicates.sorted(by: { ($0.events.first?.time ?? .distantPast) > ($1.events.first?.time ?? .distantPast) })
}

func buildStoredEventDuplicateGroups(events: [StoredSleepEvent], threshold: TimeInterval = 30 * 60) -> [StoredEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.timestamp < $1.timestamp })) { normalizeStoredEventType($0.eventType) }
    var duplicates: [StoredEventDuplicateGroup] = []

    for (normalizedType, group) in grouped {
        let clusters = clusterEventsByTime(events: group, threshold: threshold)
        for cluster in clusters where cluster.count > 1 {
            duplicates.append(
                StoredEventDuplicateGroup(
                    id: "\(normalizedType)-\(cluster.first?.id ?? UUID().uuidString)",
                    displayName: EventDisplayName.displayName(for: normalizedType),
                    events: cluster
                )
            )
        }
    }
    return duplicates.sorted(by: { ($0.events.first?.timestamp ?? .distantPast) > ($1.events.first?.timestamp ?? .distantPast) })
}

func clusterEventsByTime(events: [LoggedEvent], threshold: TimeInterval) -> [[LoggedEvent]] {
    var clusters: [[LoggedEvent]] = []
    var current: [LoggedEvent] = []

    for event in events.sorted(by: { $0.time < $1.time }) {
        guard let last = current.last else {
            current = [event]
            continue
        }
        if event.time.timeIntervalSince(last.time) <= threshold {
            current.append(event)
        } else {
            clusters.append(current)
            current = [event]
        }
    }

    if !current.isEmpty {
        clusters.append(current)
    }
    return clusters
}

func clusterEventsByTime(events: [StoredSleepEvent], threshold: TimeInterval) -> [[StoredSleepEvent]] {
    var clusters: [[StoredSleepEvent]] = []
    var current: [StoredSleepEvent] = []

    for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
        guard let last = current.last else {
            current = [event]
            continue
        }
        if event.timestamp.timeIntervalSince(last.timestamp) <= threshold {
            current.append(event)
        } else {
            clusters.append(current)
            current = [event]
        }
    }

    if !current.isEmpty {
        clusters.append(current)
    }
    return clusters
}

func normalizeLoggedEventName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
}

func eveningAnchorDate(for date: Date, hour: Int = 20, timeZone: TimeZone = .current) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = hour
    components.minute = 0
    components.second = 0
    return calendar.date(from: components) ?? date
}

// MARK: - Review Key Metrics Card (per-session)

/// Shows key metrics for a specific review night, pulling data from the
/// selected session and its events — NOT from the aggregate InsightsCalculator.
struct ReviewKeyMetricsCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]

    // MARK: - Derived per-night metrics

    private var doseIntervalText: String {
        guard let minutes = session.intervalMinutes else {
            if session.dose1Time == nil {
                return "No doses"
            }
            if session.dose2Skipped {
                return "Skipped"
            }
            return "Pending"
        }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(m)m"
    }

    private var doseIntervalColor: Color {
        guard let minutes = session.intervalMinutes else {
            return session.dose2Skipped ? .orange : .gray
        }
        if (150...240).contains(minutes) { return .green }
        return .red
    }

    private var isOnTime: Bool {
        guard let minutes = session.intervalMinutes else { return false }
        return (150...240).contains(minutes)
    }

    private var bathroomCount: Int {
        events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
    }

    private var estimatedWASO: String {
        let count = bathroomCount
        guard count > 0 else { return "0 min" }
        return "\(count * 5) min"  // ~5 min per bathroom event
    }

    private var lightsOutTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "lights_out" }
            .map(\.timestamp)
            .min()
    }

    private var finalWakeTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "wake_final" }
            .map(\.timestamp)
            .max()
    }

    private var timeInBedText: String {
        guard let lo = lightsOutTime, let wake = finalWakeTime else { return "—" }
        let minutes = TimeIntervalMath.minutesBetween(start: lo, end: wake)
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(m)m"
    }

    private var disruptionCount: Int {
        events.filter {
            let n = normalizeStoredEventType($0.eventType)
            return n == "bathroom" || n == "wake_temp" || n == "noise" || n == "pain" || n == "anxiety"
        }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key Metrics")
                    .font(.headline)
                Spacer()
                if session.dose1Time != nil {
                    HStack(spacing: 4) {
                        Image(systemName: isOnTime ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isOnTime ? .green : .orange)
                            .font(.caption)
                        Text(isOnTime ? "On-Time" : "Off-Window")
                            .font(.caption)
                            .foregroundColor(isOnTime ? .green : .orange)
                    }
                }
            }

            HStack(spacing: 12) {
                ReviewMetricTile(
                    title: "Dose Interval",
                    value: doseIntervalText,
                    icon: "clock.fill",
                    color: doseIntervalColor
                )

                ReviewMetricTile(
                    title: "Time in Bed",
                    value: timeInBedText,
                    icon: "bed.double.fill",
                    color: lightsOutTime != nil && finalWakeTime != nil ? .blue : .gray
                )
            }

            HStack(spacing: 12) {
                ReviewMetricTile(
                    title: "Disruptions",
                    value: disruptionCount == 0 ? "None" : "\(disruptionCount)",
                    icon: "exclamationmark.circle.fill",
                    color: disruptionCount == 0 ? .green : (disruptionCount <= 2 ? .yellow : .orange)
                )

                ReviewMetricTile(
                    title: "Est. WASO",
                    value: estimatedWASO,
                    icon: "moon.zzz.fill",
                    color: bathroomCount == 0 ? .green : .purple
                )
            }

            if session.snoozeCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("\(session.snoozeCount) snooze\(session.snoozeCount == 1 ? "" : "s") used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct ReviewMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

