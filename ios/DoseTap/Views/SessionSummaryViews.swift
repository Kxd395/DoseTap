import SwiftUI
import DoseCore

// MARK: - Compact Session Summary (horizontal)
struct CompactSessionSummary: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @State private var showEventsPopover = false
    
    var body: some View {
        HStack(spacing: 16) {
            CompactSummaryItem(
                icon: "1.circle.fill",
                value: core.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "–",
                label: "Dose 1",
                color: core.dose1Time != nil ? .green : .gray
            )
            
            Divider()
                .frame(height: 36)
            
            CompactSummaryItem(
                icon: "2.circle.fill",
                value: dose2Value,
                label: "Dose 2",
                color: dose2Color
            )
            
            Divider()
                .frame(height: 36)
            
            // Tappable Events item - opens sheet/popover
            Button(action: {
                showEventsPopover = true
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(eventLogger.events.count)")
                        .font(.caption.bold())
                    Text("Events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 36)
            
            CompactSummaryItem(
                icon: "bell.fill",
                value: "\(core.snoozeCount)/3",
                label: "Snooze",
                color: core.snoozeCount > 0 ? .orange : .gray
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .sheet(isPresented: $showEventsPopover) {
            TonightEventsSheet(events: eventLogger.events, onDelete: { id in
                eventLogger.deleteEvent(id: id)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var dose2Value: String {
        if let time = core.dose2Time {
            return time.formatted(date: .omitted, time: .shortened)
        }
        if core.isSkipped { return "Skip" }
        return "–"
    }
    
    private var dose2Color: Color {
        if core.dose2Time != nil { return .green }
        if core.isSkipped { return .orange }
        return .gray
    }
}

// MARK: - Live Dose Intervals Card
struct LiveDoseIntervalsCard: View {
    @ObservedObject var sessionRepo: SessionRepository
    @State private var doseEvents: [DoseCore.StoredDoseEvent] = []

    var body: some View {
        DoseIntervalsCard(doseEvents: doseEvents)
            .onAppear { load() }
            .onReceive(sessionRepo.sessionDidChange) { _ in load() }
    }

    private func load() {
        doseEvents = sessionRepo.fetchDoseEventsForActiveSession()
    }
}

// MARK: - Dose Intervals Card
struct DoseIntervalsCard: View {
    let doseEvents: [DoseCore.StoredDoseEvent]

    private struct DoseEventDisplayItem: Identifiable {
        let id: String
        let index: Int
        let timestamp: Date
        let isExtra: Bool
        let isLate: Bool
        let isEarly: Bool
    }

    private struct DoseIntervalDisplay: Identifiable {
        let id = UUID()
        let from: DoseEventDisplayItem
        let to: DoseEventDisplayItem
        let minutes: Int
    }

    private var doseDisplays: [DoseEventDisplayItem] {
        let filtered = doseEvents.filter { event in
            switch event.eventType {
            case "dose1", "dose2", "extra_dose":
                return true
            default:
                return false
            }
        }
        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }
        return sorted.enumerated().map { index, event in
            let flags = parseDoseMetadata(event.metadata)
            let isExtra = event.eventType == "extra_dose" || (index + 1) >= 3
            return DoseEventDisplayItem(
                id: event.id,
                index: index + 1,
                timestamp: event.timestamp,
                isExtra: isExtra,
                isLate: flags.isLate,
                isEarly: flags.isEarly
            )
        }
    }

    private var intervalDisplays: [DoseIntervalDisplay] {
        guard doseDisplays.count >= 2 else { return [] }
        var intervals: [DoseIntervalDisplay] = []
        for idx in 1..<doseDisplays.count {
            let from = doseDisplays[idx - 1]
            let to = doseDisplays[idx]
            let minutes = TimeIntervalMath.minutesBetween(start: from.timestamp, end: to.timestamp)
            intervals.append(DoseIntervalDisplay(from: from, to: to, minutes: minutes))
        }
        return intervals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose Intervals")
                .font(.headline)

            if intervalDisplays.isEmpty {
                Text("No dose intervals yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(intervalDisplays) { interval in
                    HStack(spacing: 8) {
                        Text("\(doseLabel(for: interval.from)) -> \(doseLabel(for: interval.to))")
                            .font(.subheadline)
                        Spacer()
                        Text(TimeIntervalMath.formatMinutes(interval.minutes))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func doseLabel(for dose: DoseEventDisplayItem) -> String {
        var label = "Dose \(dose.index)"
        if dose.index == 2 {
            if dose.isLate { label += " (Late)" }
            if dose.isEarly { label += " (Early)" }
        } else if dose.isExtra {
            label += " (Extra)"
        }
        return label
    }

    private func parseDoseMetadata(_ metadata: String?) -> (isLate: Bool, isEarly: Bool) {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, false)
        }
        let isLate = json["is_late"] as? Bool ?? false
        let isEarly = json["is_early"] as? Bool ?? false
        return (isLate, isEarly)
    }
}

// MARK: - Compact Summary Item
struct CompactSummaryItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Summary Card
struct SessionSummaryCard: View {
    @ObservedObject var core: DoseTapCore
    let eventCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight's Session")
                .font(.headline)
            
            HStack(spacing: 20) {
                SummaryItem(
                    icon: "1.circle.fill",
                    label: "Dose 1",
                    value: core.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "–",
                    color: core.dose1Time != nil ? .green : .gray
                )
                
                SummaryItem(
                    icon: "2.circle.fill",
                    label: "Dose 2",
                    value: doseValue,
                    color: dose2Color
                )
                
                SummaryItem(
                    icon: "list.bullet",
                    label: "Events",
                    value: "\(eventCount)",
                    color: .blue
                )
                
                SummaryItem(
                    icon: "bell.fill",
                    label: "Snoozes",
                    value: "\(core.snoozeCount)/3",
                    color: core.snoozeCount > 0 ? .orange : .gray
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var doseValue: String {
        if let time = core.dose2Time {
            return time.formatted(date: .omitted, time: .shortened)
        }
        if core.isSkipped {
            return "Skipped"
        }
        return "–"
    }
    
    private var dose2Color: Color {
        if core.dose2Time != nil { return .green }
        if core.isSkipped { return .orange }
        return .gray
    }
}

// MARK: - Summary Item
struct SummaryItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
