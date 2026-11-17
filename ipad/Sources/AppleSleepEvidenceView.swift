import SwiftUI
import Charts
import DoseCore

struct AppleSleepEvidenceView: View {
    let snapshot: CloudDashboardSnapshot
    @State private var selectedDay: Date?
    private let evidence: DashboardSleepEvidence?
    init(snapshot: CloudDashboardSnapshot) {
        self.snapshot = snapshot
        self.evidence = try? DashboardSleepEvidence.read(from: snapshot)
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: evidence?.timeZoneID ?? "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var days: [Date] {
        guard let evidence else { return [] }
        var result: [Date] = [], day = calendar.startOfDay(for: evidence.queryStart)
        while day < evidence.queryEnd {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }
    private var day: Date? { selectedDay.flatMap { days.contains($0) ? $0 : nil } ?? days.first }
    private var dayEnd: Date? { day.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } }
    private var samples: [SleepEvidenceSample] {
        guard let day, let dayEnd else { return [] }
        return (evidence?.samples ?? []).filter { $0.start < dayEnd && $0.end > day }
            .sorted { $0.start == $1.start ? ($0.sampleID ?? "") < ($1.sampleID ?? "") : $0.start < $1.start }
    }
    private func clockText(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
    private func dateText(_ value: Date, dateOnly: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = dateOnly ? .none : .medium
        return formatter.string(from: value)
    }
    private func source(_ sample: SleepEvidenceSample) -> String {
        sample.origin.sourceName + " · " + (sample.origin.bundleIdentifier ?? "Source ID unavailable")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Apple Health sleep evidence", systemImage: "bed.double").font(.title.bold())
            if let evidence {
                Text("\(evidence.samples.count) original samples · \(Set(evidence.samples.map { source($0) }).count) sources")
                    .font(.headline).accessibilityIdentifier("provider-sample-count")
                Text("Query: \(dateText(evidence.queryStart)) – \(dateText(evidence.queryEnd))\nPhone timezone: \(evidence.timeZoneID)\nPrepared: \(dateText(evidence.completedAt))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("This query returned readable samples, not a verified complete sleep history. Calendar-day inspection is separate from a reviewed treatment night. Overlapping sources are not added together; gaps do not mean awake.")
                    .font(.footnote)
                if evidence.samples.isEmpty {
                    Text("No readable sleep samples returned. This does not establish no sleep or whether Health read access was granted.")
                        .accessibilityIdentifier("provider-empty-query")
                } else if let day, let dayEnd {
                    Picker("Calendar day in phone timezone", selection: Binding(get: { day }, set: { selectedDay = $0 })) {
                        ForEach(days, id: \.self) { date in Text(dateText(date, dateOnly: true)).tag(date) }
                    }.pickerStyle(.menu).accessibilityIdentifier("provider-day-picker")
                    Text("\(samples.count) intervals overlap this day. Bars are clipped at midnight for display; original times remain below.")
                        .font(.footnote)
                    if !samples.isEmpty {
                        Chart(Array(samples.prefix(500)), id: \.sampleID) { sample in
                            BarMark(xStart: .value("Start", max(day, sample.start)),
                                    xEnd: .value("End", min(dayEnd, sample.end)),
                                    y: .value("Source", source(sample)))
                                .foregroundStyle(by: .value("Stage", sample.stage.rawValue))
                                .accessibilityLabel("\(source(sample)), \(sample.stage.rawValue)")
                                .accessibilityValue("\(dateText(sample.start)) to \(dateText(sample.end))")
                        }.chartXScale(domain: day...dayEnd)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                    AxisGridLine(); AxisTick()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(clockText(date))
                                        }
                                    }
                                }
                            }
                            .frame(height: 240).accessibilityIdentifier("provider-stage-chart")
                        if samples.count > 500 { Text("Chart shows the first 500 intervals; all \(samples.count) are listed below.").font(.footnote) }
                    }
                    Text("Original intervals").font(.title2.bold())
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(samples, id: \.sampleID) { sample in
                            DisclosureGroup {
                                Text("Sample: \(sample.sampleID ?? "Not supplied")\nCategory: \(sample.rawCategory)\nSource: \(source(sample))\nSource version: \(sample.origin.sourceVersion ?? "Not supplied")\nDevice: \(sample.origin.deviceModel ?? "Not supplied")\nProvider timezone: \(sample.origin.timeZoneID ?? "Not supplied")")
                                    .font(.caption).textSelection(.enabled)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sample.stage.rawValue).font(.headline)
                                    Text("\(dateText(sample.start)) → \(dateText(sample.end))")
                                    Text(sample.origin.sourceName).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("provider-interval-\(sample.sampleID ?? "unknown")")
                                .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if samples.isEmpty { Text("No samples overlap this calendar day. Coverage is unknown.") }
                }
                Text("Dose 2 awakening/return-to-sleep and sleep totals require reviewed bounds and source consensus; they are not calculated from these raw bars.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Apple Health sleep evidence was not included. On the iPhone, enable Include recent Apple Health sleep before starting a new nearby connection, then refresh this report.")
                    .accessibilityIdentifier("provider-not-included")
            }
        }.onChange(of: snapshot.sequence) { _ in selectedDay = nil }
    }
}
