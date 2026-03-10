import SwiftUI
import DoseCore

struct LiveNextActionCard: View {
    @ObservedObject var core: DoseTapCore
    let events: [LoggedEvent]
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var hasLoggedEvents: Bool {
        !events.isEmpty
    }

    private var isFinalizing: Bool {
        sessionRepo.awaitingRolloverMessage != nil
    }

    private var isPreDoseLogging: Bool {
        core.dose1Time == nil && hasLoggedEvents && !isFinalizing
    }

    private var wakeLoggedAt: Date? {
        events.first(where: { EventType($0.name) == .wakeFinal })?.time
    }

    private var headline: String {
        if isFinalizing {
            return "Next Action: Complete Morning Check-In"
        }
        if isPreDoseLogging {
            return "Pre-Dose Tracking Active"
        }
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
        if isFinalizing {
            if let wakeLoggedAt {
                return "Wake logged at \(wakeLoggedAt.formatted(date: .omitted, time: .shortened)). Complete the morning check-in to close the session and reconcile missed doses."
            }
            return sessionRepo.awaitingRolloverMessage ?? "Complete the morning check-in to close the session."
        }
        if isPreDoseLogging {
            let countLabel = hasLoggedEvents ? "\(events.count) logged event\(events.count == 1 ? "" : "s")" : "pre-dose logging"
            return "You already have \(countLabel). Take Dose 1 to unlock dose-window guidance while keeping those events attached to tonight."
        }
        guard let dose1 = core.dose1Time else {
            return "Take Dose 1 when you're ready to begin. Pre-dose events can still be logged before the session formally starts."
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
        if isFinalizing {
            return .yellow
        }
        if isPreDoseLogging {
            return .indigo
        }
        switch core.currentStatus {
        case .active:
            return .green
        case .nearClose:
            return .orange
        case .closed:
            return .red
        case .completed, .finalizing:
            return .blue
        default:
            return .indigo
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
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var titleText: String {
        if sessionRepo.awaitingRolloverMessage != nil {
            return "Session Timeline"
        }
        if core.dose1Time == nil {
            return "Pre-Dose Timeline"
        }
        return "Tonight Timeline (So Far)"
    }

    private var emptyStateText: String {
        if core.dose1Time == nil {
            return "No events logged yet. Quick log works before Dose 1."
        }
        return "No timeline events yet."
    }

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
            Text(titleText)
                .font(.headline)

            if items.isEmpty {
                Text(emptyStateText)
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

struct LoggedEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [LoggedEvent]
}

func buildLoggedEventDuplicateGroups(events: [LoggedEvent], threshold: TimeInterval = 30 * 60) -> [LoggedEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.time < $1.time })) {
        normalizeLoggedEventName($0.name)
    }
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

    return duplicates.sorted(by: {
        ($0.events.first?.time ?? .distantPast) > ($1.events.first?.time ?? .distantPast)
    })
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

func normalizeLoggedEventName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
}
