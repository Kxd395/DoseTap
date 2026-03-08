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
        let entry = currentEntry()
        // Refresh every 5 minutes while a session is active
        let refreshDate = Date().addingTimeInterval(entry.countdown != nil ? 300 : 900)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
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
