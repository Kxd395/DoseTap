import SwiftUI

struct InsightQualityBadgeRow: View {
    let session: InsightSession
    var maxVisibleFlags = 2

    private var visibleFlags: [String] {
        let normalizedFlags = session.qualityFlags.filter { !$0.isEmpty }
        guard !normalizedFlags.isEmpty else { return ["Clean"] }
        return Array(normalizedFlags.prefix(maxVisibleFlags))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleFlags, id: \.self) { flag in
                InsightBadge(text: qualityBadgeLabel(flag), tint: insightQualityColor(for: flag))
            }

            if session.qualityFlags.count > visibleFlags.count {
                InsightBadge(text: "+\(session.qualityFlags.count - visibleFlags.count)", tint: .secondary)
            }
        }
    }

    private func qualityBadgeLabel(_ flag: String) -> String {
        switch flag {
        case "Clean":
            return "Clean"
        case let value where value.contains("Missing Dose 2 outcome"):
            return "Missing D2"
        case let value where value.contains("Missing morning"):
            return "No Morning"
        case let value where value.contains("reconciled"):
            return "Reconciled"
        case let value where value.contains("Mismatch"):
            return "Mismatch"
        case let value where value.contains("Duplicate"):
            return "Duplicate"
        case let value where value.contains("Slept through"):
            return "Slept Through"
        case let value where value.contains("timing exception"):
            return "Exception"
        case let value where value.contains("early"):
            return "Early"
        case let value where value.contains("Low data completeness"):
            return "Low Data"
        default:
            return flag
        }
    }
}

struct InsightSourceBadgeRow: View {
    let session: InsightSession
    var maxVisibleSources = 3

    private var sources: [String] {
        var values = session.sourceAvailabilitySummary
        if !session.metricProvenance.isEmpty {
            values.append("Provenance")
        }
        return values
    }

    var body: some View {
        let visibleSources = Array(sources.prefix(maxVisibleSources))

        return HStack(spacing: 6) {
            if visibleSources.isEmpty {
                InsightBadge(text: "No Sources", tint: .secondary)
            } else {
                ForEach(visibleSources, id: \.self) { source in
                    InsightBadge(text: source, tint: insightSourceColor(source))
                }
            }

            if sources.count > visibleSources.count {
                InsightBadge(text: "+\(sources.count - visibleSources.count)", tint: .secondary)
            }
        }
    }
}

func insightConfidenceColor(for bucket: InsightConfidenceBucket) -> Color {
    switch bucket {
    case .high:
        return .green
    case .medium:
        return .blue
    case .low:
        return .orange
    case .insufficient:
        return .secondary
    }
}

func insightNightTypeColor(for session: InsightSession) -> Color {
    switch session.nightTypeFilter {
    case .work:
        return .blue
    case .off:
        return .teal
    case .transition:
        return .orange
    case .weekend:
        return .purple
    case .weekday, .all:
        return .secondary
    }
}

func insightWakeTypeColor(for session: InsightSession) -> Color {
    switch session.nightWakeFilter {
    case .natural:
        return .green
    case .alarm:
        return .orange
    case .mixed:
        return .purple
    case .unknown, .all:
        return .secondary
    }
}

func insightSourceColor(_ source: String) -> Color {
    switch source {
    case "Apple Health":
        return .green
    case "WHOOP":
        return .indigo
    case "Pre-sleep":
        return .pink
    case "Morning":
        return .teal
    case "Alarm diagnostics":
        return .orange
    case "Dose":
        return .blue
    case "Sleep":
        return .mint
    case "Meds":
        return .red
    case "Provenance":
        return .secondary
    default:
        return .secondary
    }
}

private func insightQualityColor(for flag: String) -> Color {
    switch flag {
    case "Clean":
        return .green
    case let value where value.contains("Missing"):
        return .orange
    case let value where value.contains("Mismatch"):
        return .red
    case let value where value.contains("Duplicate"):
        return .orange
    case let value where value.contains("Slept through"):
        return .red
    case let value where value.contains("exception"):
        return .purple
    case let value where value.contains("early"):
        return .orange
    default:
        return .secondary
    }
}
