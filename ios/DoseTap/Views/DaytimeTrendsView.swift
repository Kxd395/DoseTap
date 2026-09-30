import SwiftUI
import Charts
import DoseCore

struct DaytimeTrendsView: View {
    private enum Range: String, CaseIterable { case twoWeeks = "14D", fourWeeks = "28D", sixMonths = "6M", year = "12M", custom = "Custom" }
    @ObservedObject private var repository = SessionRepository.shared
    @State private var range: Range = .fourWeeks
    @State private var start = Date()
    @State private var end = Date()
    @State private var origin: DaytimeCheckIn.Origin?
    @State private var setting: DaytimeCheckIn.Setting?
    @State private var observations: [DaytimeCheckIn] = []
    @State private var events: [DaytimeEvent] = []
    @State private var report: DaytimeDiaryAnalysis?
    @State private var failure: String?
    @State private var loaded = false
    var body: some View {
        List {
            Section("Period and sampling") {
                Picker("Period", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.onChange(of: range) { _ in applyRange(); calculate() }
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...Date())
                    DatePicker("Through", selection: $end, in: ...Date())
                }
                Picker("Entry type", selection: $origin) {
                    Text("All entry types").tag(DaytimeCheckIn.Origin?.none)
                    ForEach(DaytimeCheckIn.Origin.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                Picker("Setting", selection: $setting) {
                    Text("All settings").tag(DaytimeCheckIn.Setting?.none)
                    ForEach(DaytimeCheckIn.Setting.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Text("\(start.formatted()) – \(end.formatted()) · \(TimeZone.current.identifier)").font(.caption)
                Button("Refresh", action: reload)
            }
            if let failure { Section { Text(failure).foregroundStyle(.red) } }
            if let report {
                Section("Observed diary samples") {
                    Text("\(report.answeredCount) answered ratings on \(report.ratedCalendarDays) calendar dates; \(report.observations.count) entries including incomplete, unsure and skipped responses.")
                    if report.answeredCount > 0 {
                        Chart(report.observations) { row in
                            if let score = row.response {
                                PointMark(x: .value("Assessed at", row.assessedAt), y: .value("Custom sleepiness 0–10", score))
                                    .foregroundStyle(by: .value("Entry type", row.origin.title))
                                    .accessibilityLabel("\(row.assessedAt.formatted()), \(score) of 10, \(row.origin.title)")
                            }
                        }.chartYScale(domain: 0...10).frame(height: 220)
                    }
                    Text("Each point is a reported observation. Gaps are unmeasured; no continuous sleepiness level or clinical score is inferred.").font(.caption)
                }
                Section("Comparable samples") {
                    Text("Groups retain actual local clock band, timezone, setting, entry type and sampling protocol. Repeated entries are samples, not additional days.").font(.caption)
                    ForEach(report.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.clockBandLabel) · \(group.origin.title) · \(group.setting.rawValue)").font(.headline)
                            Text(group.timeZoneIdentifier).font(.caption)
                            Text(group.samplingProtocolLabel ?? (group.origin == .scheduled ? "Schedule definition unavailable" : "Unscheduled observations"))
                                .font(.caption)
                            Text("\(group.answeredCount)/\(group.entryCount) entries answered on \(group.ratedDays) dates. Median: \(group.median.map { String(format: "%.1f / 10", $0) } ?? "Unavailable")")
                            Text("\(group.firstAssessedAt.formatted()) – \(group.lastAssessedAt.formatted())").font(.caption)
                            Text(group.distribution.isEmpty ? "No answered ratings" : "Distribution: " + group.distribution.keys.sorted().map { "\($0): \(group.distribution[$0] ?? 0)" }.joined(separator: "; ")).font(.caption)
                        }
                    }
                }
                Section("Explicit event and review coverage") {
                    Text("\(report.unplannedSleepEvents) reported unplanned-sleep events in this period, counted once per event. Event counts include all entry types.")
                    ForEach(DaytimeEvent.Kind.allCases.filter { $0 != .unplannedSleep }, id: \.self) { kind in
                        Text("\(kind.rawValue): \(report.eventCountsByKind[kind] ?? 0) distinct events")
                    }
                    Text("\(report.copingResponseCounts[.yes] ?? 0) check-ins report trying to stay awake; \(report.copingResponseCounts[.unanswered] ?? 0) did not answer. These are observation responses, not event counts.")
                    Text("\(report.reviewedCalendarDays) dates touched by definite review intervals: \(report.fullyReviewedCalendarDays) fully covered, \(report.partiallyReviewedCalendarDays) partially covered. \(report.daysWithoutReviewedInterval) dates have no definite reviewed interval.")
                    Text("Review coverage follows the selected entry filters. A reviewed interval can contain reported symptoms; it is not proof of a symptom-free day. Uncertain and unreviewed intervals remain unknown.").font(.caption)
                }
                Section("Observation table") {
                    ForEach(report.observations) { row in
                        VStack(alignment: .leading) {
                            Text(row.assessedAt.formatted()).font(.headline)
                            Text("\(row.response.map { "\($0)/10" } ?? row.status.rawValue) · \(row.origin.title) · \(row.setting.rawValue)")
                            Text("Recorded \(row.recordedAt.formatted()); source timezone \(row.timeZoneIdentifier)").font(.caption)
                            if let label = row.samplingProtocolLabel { Text("Saved reminder: \(label)").font(.caption) }
                        }
                    }
                }
            }
        }.navigationTitle("Daytime trends")
            .onAppear { applyRange(); reload() }
            .onChange(of: start) { _ in calculate() }.onChange(of: end) { _ in calculate() }
            .onChange(of: origin) { _ in calculate() }.onChange(of: setting) { _ in calculate() }
    }
    private func applyRange() {
        guard range != .custom else { return }
        end = Date(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        switch range {
        case .twoWeeks: start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: end)) ?? end
        case .fourWeeks: start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: end)) ?? end
        case .sixMonths: start = calendar.date(byAdding: .month, value: -6, to: end) ?? end
        case .year: start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
        case .custom: break
        }
    }
    private func reload() {
        do { observations = try repository.daytimeCheckIns().current; events = try repository.daytimeEvents().current; loaded = true; calculate() }
        catch { loaded = false; observations = []; events = []; report = nil; failure = DaytimeDiaryError.unreadable.localizedDescription }
    }
    private func calculate() {
        guard loaded else { return }
        do {
            report = try DaytimeDiaryAnalysis(observations: observations.filter { (origin == nil || $0.origin == origin) && (setting == nil || $0.setting == setting) },
                events: events, start: start, end: end, now: Date(), timeZone: .current)
            failure = nil
        } catch { report = nil; failure = "Choose a valid period ending no later than now. Saved records are unchanged." }
    }
}
