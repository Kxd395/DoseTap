import SwiftUI
import DoseCore

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
    let healthSnapshot: HealthDataSnapshotModel?

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

            DoseTimingCard(sessionKey: session.sessionDate)
            NightScoreCard(sessionKey: session.sessionDate)
            ReviewKeyMetricsCard(session: session, events: events)
            PreSleepLogCard(sessionKey: session.sessionDate)
            MorningCheckInCard(sessionKey: session.sessionDate)

            MergedNightTimelineCard(
                session: session,
                events: events,
                nightDate: nightDate,
                showFullViewLink: false,
                snapshotTimeline: snapshotTimeline,
                allowLiveTimelineFallback: false
            )

            if let healthSnapshot {
                HealthDataSnapshotCard(snapshot: healthSnapshot)
            }

            InsightsSummaryCard(title: "Last 14-Night Trends", showDefinitions: true)
            ReviewEventsSnapshotCard(events: events)
            ExportCard(sessionKey: session.sessionDate)

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

struct StoredEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [StoredSleepEvent]
}

func buildStoredEventDuplicateGroups(events: [StoredSleepEvent], threshold: TimeInterval = 30 * 60) -> [StoredEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.timestamp < $1.timestamp })) {
        normalizeStoredEventType($0.eventType)
    }
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

    return duplicates.sorted(by: {
        ($0.events.first?.timestamp ?? .distantPast) > ($1.events.first?.timestamp ?? .distantPast)
    })
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

func eveningAnchorDate(for date: Date, hour: Int = 20, timeZone: TimeZone = .current) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = hour
    components.minute = 0
    components.second = 0
    return calendar.date(from: components) ?? date
}
