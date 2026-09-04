// DoseTapWidgets.swift — P2-1 WidgetKit extension source
// This file should live in a WidgetKit extension target.
// Add via Xcode: File → New → Target → Widget Extension → "DoseTapWidget"
// Then move this file into that target.
import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct DoseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoseTimelineEntry {
        DoseTimelineEntry(date: Date(), state: SharedDoseState())
    }

    func getSnapshot(in context: Context, completion: @escaping (DoseTimelineEntry) -> Void) {
        let state = SharedDoseState.load() ?? SharedDoseState()
        completion(DoseTimelineEntry(date: Date(), state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseTimelineEntry>) -> Void) {
        let state = SharedDoseState.load() ?? SharedDoseState()
        let entry = DoseTimelineEntry(date: Date(), state: state)

        // Refresh every 5 minutes during active window, otherwise every 15 minutes
        let refreshInterval: TimeInterval = (state.phase == .windowOpen || state.phase == .waiting) ? 300 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct DoseTimelineEntry: TimelineEntry {
    let date: Date
    let state: SharedDoseState
}

// MARK: - Home Screen Widget (systemSmall / systemMedium)

struct DoseStatusWidgetView: View {
    let entry: DoseTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phaseIcon)
                    .font(.title2)
                    .foregroundColor(phaseColor)
                Spacer()
            }

            Text(entry.state.phase.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundColor(phaseColor)

            Spacer()

            if let countdown = entry.state.countdownMinutes {
                Text("\(countdown)m")
                    .font(.title.bold())
                    .monospacedDigit()
                Text(entry.state.phase == .waiting ? "until window" : "remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(statusSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .modifier(WidgetContainerBackground())
    }

    private var mediumWidget: some View {
        HStack {
            // Left: status
            VStack(alignment: .leading, spacing: 4) {
                Label(entry.state.phase.rawValue, systemImage: phaseIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(phaseColor)

                if let d1 = entry.state.dose1Time {
                    Text("D1: \(d1.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                }
                if let d2 = entry.state.dose2Time {
                    Text("D2: \(d2.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                } else if entry.state.dose2Skipped {
                    Text("D2: Skipped")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Right: countdown
            if let countdown = entry.state.countdownMinutes {
                VStack {
                    Text("\(countdown)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(phaseColor)
                    Text("minutes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .modifier(WidgetContainerBackground())
    }

    // MARK: - Helpers

    private var phaseIcon: String {
        switch entry.state.phase {
        case .noDose:     return "moon.zzz"
        case .waiting:    return "clock"
        case .windowOpen: return "pills.fill"
        case .complete:   return "checkmark.circle.fill"
        case .skipped:    return "forward.fill"
        case .expired:    return "exclamationmark.triangle"
        }
    }

    private var phaseColor: Color {
        switch entry.state.phase {
        case .noDose:     return .secondary
        case .waiting:    return .blue
        case .windowOpen: return .green
        case .complete:   return .green
        case .skipped:    return .orange
        case .expired:    return .red
        }
    }

    private var statusSummary: String {
        switch entry.state.phase {
        case .noDose:     return "Start your session"
        case .waiting:    return "Dose 1 taken"
        case .windowOpen: return "Window is open!"
        case .complete:   return "Session complete"
        case .skipped:    return "Dose 2 was skipped"
        case .expired:    return "Window has expired"
        }
    }
}

// MARK: - Lock Screen Widget (accessoryCircular / accessoryRectangular)

struct DoseLockScreenWidgetView: View {
    let entry: DoseTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        case .accessoryInline:
            inlineWidget
        default:
            circularWidget
        }
    }

    private var circularWidget: some View {
        ZStack {
            if let countdown = entry.state.countdownMinutes {
                // Show progress ring
                let total: Double = entry.state.phase == .waiting ? 150 : 90
                let progress = 1.0 - (Double(countdown) / total)
                AccessoryWidgetBackground()
                Gauge(value: progress) {
                    Text("\(countdown)")
                        .font(.system(.body, design: .rounded).bold())
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                AccessoryWidgetBackground()
                Image(systemName: entry.state.phase == .complete ? "checkmark" : "moon.zzz")
                    .font(.title3)
            }
        }
    }

    private var rectangularWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.state.phase.rawValue, systemImage: "pills.fill")
                .font(.caption.weight(.semibold))
            if let countdown = entry.state.countdownMinutes {
                Text("\(countdown) min \(entry.state.phase == .waiting ? "until window" : "remaining")")
                    .font(.caption2)
            }
            if let d1 = entry.state.dose1Time {
                Text("D1 at \(d1.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var inlineWidget: some View {
        if let countdown = entry.state.countdownMinutes {
            Label("\(countdown)m \(entry.state.phase == .waiting ? "to window" : "left")", systemImage: "pills.fill")
        } else {
            Label(entry.state.phase.rawValue, systemImage: "pills.fill")
        }
    }
}

// MARK: - Widget Declarations

struct DoseStatusWidget: Widget {
    let kind = "DoseStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            DoseStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Dose Status")
        .description("See your current dose status and countdown timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DoseLockScreenWidget: Widget {
    let kind = "DoseLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            DoseLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Dose Countdown")
        .description("Quick dose countdown for your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Widget Bundle (entry point for the extension target)

// Uncomment this when adding to the Widget Extension target:
// @main
struct DoseTapWidgetBundle: WidgetBundle {
    var body: some Widget {
        DoseStatusWidget()
        DoseLockScreenWidget()
    }
}

// MARK: - iOS 17+ Container Background Compat
/// Applies `.containerBackground(for: .widget)` on iOS 17+, no-op on older.
private struct WidgetContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        } else {
            content.background(Color(.systemBackground))
        }
    }
}
