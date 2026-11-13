import SwiftUI
import Charts
import DoseCore

struct DaytimeTrendsView: View {
    private enum Range: String, CaseIterable { case twoWeeks = "14D", fourWeeks = "28D", sixMonths = "6M", year = "12M", custom = "Custom" }
    @ObservedObject private var repository: SessionRepository
    let sharedSelection: DaytimeTrendSelection?
    let sharedInspection: Binding<DaytimeInspectionState>?
    let refreshShared: (() -> Void)?
    let now: () -> Date
    @MainActor init(repository: SessionRepository? = nil, sharedSelection: DaytimeTrendSelection? = nil,
         sharedInspection: Binding<DaytimeInspectionState>? = nil, refreshShared: (() -> Void)? = nil, now: @escaping () -> Date = Date.init) {
        self.sharedInspection = sharedInspection; self.repository = repository ?? .shared; self.sharedSelection = sharedSelection; self.refreshShared = refreshShared; self.now = now
        let initial = sharedSelection?.asOf ?? now(); _start = State(initialValue: initial); _end = State(initialValue: initial)
    }
    @State private var range: Range = .fourWeeks
    @State private var start: Date
    @State private var end: Date
    @State private var localInspection = DaytimeInspectionState()
    private var inspection: Binding<DaytimeInspectionState> { sharedInspection ?? $localInspection }
    private var selectedID: UUID? { inspection.wrappedValue.selectedObservationID }
    private var origin: DaytimeCheckIn.Origin? { inspection.wrappedValue.origin }
    private var setting: DaytimeCheckIn.Setting? { inspection.wrappedValue.setting }
    @State private var records: DaytimeTrendRecords?
    @State private var capture: DaytimeTrendSelection?
    @State private var basis: WorkContextBasis = .confirmed
    @State private var report: DaytimeDiaryAnalysis?
    @State private var failure: String?
    var body: some View {
        List {
            if let failure { Section { Text(failure).foregroundStyle(.red) } }
            Section("Observed diary samples") {
                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted)) · \(capture?.timeZone.identifier ?? TimeZone.current.identifier)").font(.caption)
                if let report {
                    if report.answeredCount > 0, start < end {
                        Chart(report.observations) { row in
                            if let score = row.response {
                                PointMark(x: .value("Assessed at", row.assessedAt), y: .value("Custom sleepiness 0–10", score))
                                    .foregroundStyle(by: .value("Entry type", row.origin.title))
                                    .symbolSize(row.id == selectedID ? 160 : 40)
                                    .accessibilityLabel("\(row.assessedAt.formatted()), \(score) of 10, \(row.origin.title)")
                            }
                        }.chartXScale(domain: start...end).chartYScale(domain: 0...10)
                            .chartXAxis {
                                AxisMarks(values: [0.2, 0.5, 0.8].map { start.addingTimeInterval(end.timeIntervalSince(start) * $0) }) { _ in
                                    AxisGridLine(); AxisTick()
                                    AxisValueLabel(format: end.timeIntervalSince(start) < 172800 ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    Rectangle().fill(.clear).contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { gesture in
                                        let frame = geometry[proxy.plotAreaFrame], x = gesture.location.x - frame.origin.x
                                        guard x >= 0, x <= frame.width, let time: Date = proxy.value(atX: x) else { return }
                                        let left: Date? = proxy.value(atX: max(0, x - 8))
                                        let right: Date? = proxy.value(atX: min(frame.width, x + 8))
                                        let tolerance = max(left.map { abs($0.timeIntervalSince(time)) } ?? 0, right.map { abs($0.timeIntervalSince(time)) } ?? 0)
                                        inspection.wrappedValue.offer(at: time, observations: report.observations, tolerance: tolerance)
                                    })
                                }
                            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(height: 220).accessibilityIdentifier("daytime-trend-chart")
                    } else { Text("No answered ratings in this period. Missing observations are not zero sleepiness.") }
                    Text("\(report.answeredCount) ratings on \(report.ratedCalendarDays) dates; \(report.observations.count) entries including unanswered responses.")
                    if let selected = report.observations.first(where: { $0.id == selectedID }) {
                        VStack(alignment: .leading) {
                            Text("Selected saved observation").font(.headline)
                            Text("\(selected.assessedAt.formatted()) · \(selected.response.map { "\($0)/10" } ?? selected.status.rawValue)")
                            Text("Recorded \(selected.recordedAt.formatted()); source timezone \(selected.timeZoneIdentifier)").font(.caption)
                            Text("\(selected.origin.title) · \(selected.instrumentID) · \(selected.contentVersion)").font(.caption)
                            if let context = report.observationContexts?[selected.id] {
                                Text(context.label).font(.caption)
                                DisclosureGroup("Source references") {
                                    Text("Context calculated at \(context.asOf.formatted())").font(.caption)
                                    ForEach(context.sourceRecordIDs, id: \.self) { Text($0).font(.caption.monospaced()) }
                                }
                            }
                            if let wake = records?.wakeContexts[selected.id] {
                                Text(wake.label).font(.caption)
                                DisclosureGroup("Main-wake source references") {
                                    Text("Main-wake context v\(wake.definitionVersion) · \(wake.status.rawValue)").font(.caption)
                                    Text(wake.elapsedSeconds.map { "Exact elapsed seconds: \($0)" } ?? "Elapsed time unavailable").font(.caption)
                                    ForEach(wake.originalReferences, id: \.self) { original in
                                        Text("Saved wake: \(original.at.formatted(date: .complete, time: .complete)) · \(original.sourceID) · \(original.revision)").font(.caption)
                                    }
                                    if let current = wake.currentSource {
                                        Text("Current source wake: \(current.reference.at.formatted(date: .complete, time: .complete)); recorded \(current.recordedAt.formatted(date: .complete, time: .complete))").font(.caption)
                                    }
                                }
                            }
                        }.accessibilityIdentifier("daytime-selected-observation-\(selected.id.uuidString)")
                    }
                } else if failure == nil { Text("No daytime history was collected for these bounds.") }
                Text("Daytime calendar dates; night dose, work-phase and context filters do not apply.").font(.caption)
                Text("Points are actual reported observations. Selection snaps to a saved point; gaps are unmeasured. No continuous level or clinical score is inferred.").font(.caption)
            }
            inspectionControls
            samplingControls
            if let report {
                if let issue = capture?.contextIssue { Section("Comparison context unavailable") { Text(issue) } }
                Section("Comparable samples") {
                    Text("Groups retain actual local clock band, timezone, setting, entry type and sampling protocol. Repeated entries are samples, not additional days.").font(.caption)
                    Text(report.contextScopeLabel).font(.caption)
                    ForEach(capture?.contextIssue == nil ? report.groups : []) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.clockBandLabel) · \(group.origin.title) · \(group.setting.rawValue)").font(.headline)
                            Text(group.timeZoneIdentifier).font(.caption)
                            if let context = group.contextLabel { Text(context).font(.caption) }
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
                            Button(row.assessedAt.formatted()) { inspection.wrappedValue.select(row.id) }.font(.headline).accessibilityIdentifier("daytime-select-observation-\(row.id.uuidString)")
                            Text("\(row.response.map { "\($0)/10" } ?? row.status.rawValue) · \(row.origin.title) · \(row.setting.rawValue)")
                            Text("Recorded \(row.recordedAt.formatted()); source timezone \(row.timeZoneIdentifier)").font(.caption)
                            if row.id == selectedID { Label("Selected observation", systemImage: "checkmark.circle.fill").accessibilityIdentifier("daytime-selected-row") }
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
    private var inspectionControls: some View {
        Section("Inspect saved observations") {
            if !inspection.wrappedValue.offeredCandidateIDs.isEmpty {
                Text("Several saved points share this position. Choose an observation; the previous selection is retained.")
                ForEach(inspection.wrappedValue.offeredCandidateIDs, id: \.self) { id in
                    if let row = report?.observations.first(where: { $0.id == id }) {
                        Button("\(row.assessedAt.formatted()) · \(row.response.map { "\($0)/10" } ?? row.status.rawValue) · \(row.origin.title) · \(row.id.uuidString.prefix(8))") {
                            inspection.wrappedValue.select(id)
                        }.accessibilityIdentifier("daytime-overlap-candidate-\(id.uuidString)")
                    } else { Text("Candidate \(id.uuidString.prefix(8)) is outside the visible data. Its identity is retained.") }
                }
                Button("Dismiss candidates") { inspection.wrappedValue.offeredCandidateIDs = [] }
            }
            if let id = selectedID, report?.observations.contains(where: { $0.id == id }) != true {
                Text(retainedSelectionMessage(id)).accessibilityIdentifier("daytime-retained-selection")
            }
            Button("Previous observation") { inspection.wrappedValue.move(-1, observations: report?.observations ?? []) }
                .disabled(inspection.wrappedValue.neighbor(-1, observations: report?.observations ?? []) == nil)
            Button("Next observation") { inspection.wrappedValue.move(1, observations: report?.observations ?? []) }
                .disabled(inspection.wrappedValue.neighbor(1, observations: report?.observations ?? []) == nil)
            Button("Reset selection") { inspection.wrappedValue.resetSelection() }.disabled(selectedID == nil && inspection.wrappedValue.offeredCandidateIDs.isEmpty)
            Button("Reset entry filters") { inspection.wrappedValue.resetFilters() }.disabled(origin == nil && setting == nil)
        }
    }
    private func retainedSelectionMessage(_ id: UUID) -> String {
        let prefix = "Selected observation \(id.uuidString.prefix(8)) is retained. "
        guard failure == nil, let records else { return prefix + "Records are unavailable or updating; refresh to retry." }
        guard let row = records.observations.first(where: { $0.id == id }) else { return prefix + "It is unavailable at this capture time. No replacement was selected." }
        if row.assessedAt < start || row.assessedAt >= end { return prefix + "It is outside the selected period. Return to its period to inspect it." }
        return prefix + "It is hidden by the entry filters. Reset those filters to inspect it."
    }
    private var samplingControls: some View {
        Section {
            DisclosureGroup("Period, entry type and setting") {
                Text("Exact bounds: \(start.formatted()) – \(end.formatted()) (exclusive); captured \(capture?.asOf.formatted() ?? "unavailable").").font(.caption)
                if sharedSelection == nil {
                    Picker("Period", selection: $range) {
                        ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.onChange(of: range) { _ in applyRange(); reload() }
                    if range == .custom {
                        DatePicker("From", selection: $start, in: ...(capture?.asOf ?? now()))
                        DatePicker("Until (exclusive)", selection: $end, in: ...(capture?.asOf ?? now()))
                    }
                    Picker("Work basis", selection: $basis) {
                        ForEach(WorkContextBasis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.onChange(of: basis) { _ in reload() }
                } else { Text("Period and work basis follow the Dashboard selection.").font(.caption) }
                Picker("Entry type", selection: inspection.origin) {
                    Text("All entry types").tag(DaytimeCheckIn.Origin?.none)
                    ForEach(DaytimeCheckIn.Origin.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.accessibilityIdentifier("daytime-origin-filter")
                Picker("Setting", selection: inspection.setting) {
                    Text("All settings").tag(DaytimeCheckIn.Setting?.none)
                    ForEach(DaytimeCheckIn.Setting.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Button("Refresh") { if let refreshShared { refreshShared() } else { reload() } }
            }
        }
    }
    private var selectedRange: DashboardReportingRange {
        switch range {
        case .twoWeeks: return .twoWeeks
        case .fourWeeks: return .fourWeeks
        case .sixMonths: return .sixMonths
        case .year: return .year
        case .custom: return .custom
        }
    }
    private func applyRange() {
        guard sharedSelection == nil, range != .custom,
              let window = try? selectedRange.daytimeWindow(asOf: now(), timeZone: .current), let lower = window.start else { return }
        start = lower; end = window.endExclusive
    }
    private func reload() {
        do {
            let asOf = sharedSelection?.asOf ?? now()
            records = try DaytimeTrendRecords(repository: repository, asOf: asOf)
            if let sharedSelection { capture = sharedSelection }
            else {
                var work: WorkContextDocument?, medication: DashboardContextTimeline?, issue: String?
                do {
                    work = try repository.workContext()
                    medication = try DashboardContextTimeline(presets: repository.medicationPresetExportSnapshot(), content: [], capturedAt: asOf)
                } catch { issue = "Comparison context could not be read. Raw observations remain available; refresh to retry." }
                let reviewed = range == .custom ? try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end), ledger: .init(), asOf: asOf, timeZone: .current) : nil
                capture = .init(range: selectedRange, asOf: asOf, timeZone: .current, reviewedPeriod: reviewed, work: work, medication: medication, basis: basis, contextIssue: issue)
            }
            calculate()
        } catch { records = nil; report = nil; capture = nil; failure = "Daytime records or reporting bounds could not be read. Refresh to retry; saved records are unchanged." }
    }
    private func calculate() {
        guard let records, var selection = capture else { return }
        do {
            if sharedSelection == nil, range == .custom {
                let reviewed = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end), ledger: .init(), asOf: selection.asOf, timeZone: selection.timeZone)
                selection = .init(range: .custom, asOf: selection.asOf, timeZone: selection.timeZone, reviewedPeriod: reviewed, work: selection.work, medication: selection.medication, basis: selection.basis, contextIssue: selection.contextIssue)
                capture = selection
            }
            let window = try selection.window(earliestEvidenceAt: records.earliestEvidenceAt)
            guard let lower = window.start, !window.isEmpty else { report = nil; failure = nil; start = window.endExclusive; end = window.endExclusive; return }
            start = lower; end = window.endExclusive
            let rows = records.observations.filter { (origin == nil || $0.origin == origin) && (setting == nil || $0.setting == setting) }
            let contexts = selection.contextIssue == nil ? try Dictionary(uniqueKeysWithValues: rows.map {
                ($0.id, try DaytimeObservationContext(observation: $0, work: selection.work, basis: selection.basis, medication: selection.medication, asOf: selection.asOf, wake: records.wakeContexts[$0.id]))
            }) : nil
            report = try DaytimeDiaryAnalysis(observations: rows, events: records.events, start: lower, end: window.endExclusive,
                now: selection.asOf, timeZone: selection.timeZone, includesEnd: false, contexts: contexts)
            failure = nil
        } catch { report = nil; failure = "Choose valid dates within the captured period, or Refresh to retry. Saved records are unchanged." }
    }
}
