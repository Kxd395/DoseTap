// WatchComplications.swift — P2-3 WidgetKit complications for watchOS
// Provides lock screen / watch face complications using the SharedDoseState data.
#if os(watchOS)
import WidgetKit
import SwiftUI

// MARK: - Complication Timeline Provider

@available(watchOS 9.0, *)
struct DoseComplicationProvider: TimelineProvider {
    typealias Entry = DoseComplicationEntry

    func placeholder(in context: Context) -> DoseComplicationEntry {
        DoseComplicationEntry(date: Date(), phase: "Waiting…", countdown: nil, icon: "pills.fill")
    }

    func getSnapshot(in context: Context, completion: @escaping (DoseComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseComplicationEntry>) -> Void) {
        let now = Date()

        // When a session is active, pre-generate one entry per minute so the
        // countdown digit updates live on the watch face without requiring a
        // timeline reload. Without this the number visibly stalls until the
        // widget system reloads us (typically every 5+ minutes).
        guard let state = SharedDoseState.load(),
              let d1 = state.dose1Time,
              state.dose2Time == nil,
              !state.dose2Skipped else {
            let entry = currentEntry()
            // Quiet state: refresh in 15 min.
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        var entries: [DoseComplicationEntry] = []
        // Emit a minute-by-minute timeline for up to the next 60 minutes,
        // capped at the window-close moment. After that, ask to reload.
        let windowClose = d1.addingTimeInterval(240 * 60)
        let horizon = min(windowClose, now.addingTimeInterval(60 * 60))
        var t = now
        while t <= horizon {
            entries.append(entryFor(state: state, at: t))
            t = t.addingTimeInterval(60)
        }
        if entries.isEmpty { entries.append(currentEntry()) }

        // Reload shortly after the last entry so we keep the digits fresh.
        let refreshDate = (entries.last?.date ?? now).addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    private func entryFor(state: SharedDoseState, at date: Date) -> DoseComplicationEntry {
        // Re-derive countdown at the future date so each entry shows its own number.
        let countdown: Int? = {
            guard let d1 = state.dose1Time, state.dose2Time == nil, !state.dose2Skipped else { return nil }
            let elapsed = date.timeIntervalSince(d1) / 60
            if elapsed < 150 { return Int(150 - elapsed) }
            if elapsed <= 240 { return Int(240 - elapsed) }
            return nil
        }()
        return DoseComplicationEntry(
            date: date,
            phase: state.phase.rawValue,
            countdown: countdown,
            icon: iconForPhase(state.phase)
        )
    }

    private func currentEntry() -> DoseComplicationEntry {
        // Try to read from App Group (same as iOS widget)
        if let state = SharedDoseState.load() {
            return DoseComplicationEntry(
                date: Date(),
                phase: state.phase.rawValue,
                countdown: state.countdownMinutes,
                icon: iconForPhase(state.phase)
            )
        }
        // Fallback — no synced state yet
        return DoseComplicationEntry(date: Date(), phase: "No data", countdown: nil, icon: "moon.zzz")
    }

    private func iconForPhase(_ phase: SharedDoseState.WidgetPhase) -> String {
        switch phase {
        case .noDose:     return "moon.zzz"
        case .waiting:    return "clock"
        case .windowOpen: return "pills.fill"
        case .complete:   return "checkmark.circle.fill"
        case .skipped:    return "forward.fill"
        case .expired:    return "exclamationmark.triangle"
        }
    }
}

// MARK: - Timeline Entry

@available(watchOS 9.0, *)
struct DoseComplicationEntry: TimelineEntry {
    let date: Date
    let phase: String
    let countdown: Int?
    let icon: String
}

// MARK: - Circular Complication

@available(watchOS 9.0, *)
struct DoseCircularComplication: View {
    let entry: DoseComplicationEntry

    var body: some View {
        if let mins = entry.countdown {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(mins)")
                        .font(.system(.title3, design: .rounded).bold())
                    Text("min")
                        .font(.system(.caption2))
                        .foregroundColor(.secondary)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.icon)
                    .font(.title3)
            }
        }
    }
}

// MARK: - Rectangular Complication

@available(watchOS 9.0, *)
struct DoseRectangularComplication: View {
    let entry: DoseComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.phase, systemImage: entry.icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let mins = entry.countdown {
                Text("\(mins) min remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Inline Complication

@available(watchOS 9.0, *)
struct DoseInlineComplication: View {
    let entry: DoseComplicationEntry

    var body: some View {
        if let mins = entry.countdown {
            Label("\(mins)m left", systemImage: "pills.fill")
        } else {
            Label(entry.phase, systemImage: entry.icon)
        }
    }
}

// MARK: - Widget Declarations

@available(watchOS 9.0, *)
struct DoseComplicationCircular: Widget {
    let kind = "DoseComplicationCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseComplicationProvider()) { entry in
            DoseCircularComplication(entry: entry)
        }
        .configurationDisplayName("Dose Timer")
        .description("Countdown to your next dose window.")
        .supportedFamilies([.accessoryCircular])
    }
}

@available(watchOS 9.0, *)
struct DoseComplicationRectangular: Widget {
    let kind = "DoseComplicationRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseComplicationProvider()) { entry in
            DoseRectangularComplication(entry: entry)
        }
        .configurationDisplayName("Dose Status")
        .description("Current dose status and countdown.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@available(watchOS 9.0, *)
struct DoseComplicationInline: Widget {
    let kind = "DoseComplicationInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseComplicationProvider()) { entry in
            DoseInlineComplication(entry: entry)
        }
        .configurationDisplayName("Dose")
        .description("Quick dose countdown.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - Watch Widget Bundle

@available(watchOS 9.0, *)
struct DoseTapWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DoseComplicationCircular()
        DoseComplicationRectangular()
        DoseComplicationInline()
    }
}
#endif
