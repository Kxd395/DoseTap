import SwiftUI
import Charts
import DoseCore
struct SleepNapsDashboardView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @StateObject private var napCheck = NapProviderCheck()
    @StateObject private var mainCheck = TimelineDoseSleepModel()
    @State private var document: NapDiaryDocument?
    @State private var storedRevision: UUID?
    @State private var timers: [NapEpisode] = []
    @State private var failure: String?
    private var selectedDay: Date {
        get { model.napInspection.selectedDay ?? calendarExtent.upperBound }
        nonmutating set { model.napInspection.selectDay(newValue) }
    }
    private var calendarPage: Int { model.napInspection.visiblePage(dayCount: calendarDayCount) }
    @State private var napAsOf = Date()
    private var selectedNap: String? {
        get { model.napInspection.selectedEpisodeID }
        nonmutating set { if let newValue { model.napInspection.selectEpisode(newValue) } else { model.napInspection.clearSelection() } }
    }
    private var selectedMain: String? { model.inspection.selectedObservationID }
    @State private var editing: NapEpisode?
    @State private var adding = false
    @State private var completeness: NapCompleteness?
    @State private var exportText: String?
    private var zone: String { model.reportingTimeZone.identifier }
    private var day: String { NapEpisode.day(selectedDay, zone) }
    private var all: [NapEpisode] { document?.merging(timers) ?? [] }
    private var napWindow: DashboardDaytimeWindow? {
        try? model.selectedRange.daytimeWindow(asOf: model.reportingAsOf, timeZone: model.reportingTimeZone,
            reviewedPeriod: model.reportingPeriod, earliestEvidenceAt: (all.compactMap { NapPeriodEligibility.dayBounds($0)?.0 }
                + (document?.reviews.compactMap { NapPeriodEligibility.dayBounds(day: $0.day, timeZoneID: $0.timeZoneID)?.0 } ?? [])).min())
    }
    private var eligible: [NapEpisode] { let window = napWindow; return all.map { row in var value = row; if NapPeriodEligibility.exclusion(row, in: window) != nil { value.estimatedSleepMinutes = nil }; return value } }
    private var rows: [NapEpisode] {
        let window = napWindow
        return all.filter { NapPeriodEligibility.isVisible($0, in: window) }.sorted { $0.day == $1.day ? $0.id < $1.id : $0.day > $1.day }
    }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = model.reportingTimeZone; return value }
    private var calendarExtent: ClosedRange<Date> {
        let last = min(napAsOf, napWindow?.endExclusive.addingTimeInterval(-0.001) ?? napAsOf)
        let firstKey = (rows.map(\.day) + model.visibleInspectionNights.map(\.sessionDate)).min()
        let format = DateFormatter(); format.calendar = calendar; format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = model.reportingTimeZone; format.dateFormat = "yyyy-MM-dd"
        let first = napWindow?.start ?? firstKey.flatMap(format.date(from:)) ?? calendar.startOfDay(for: last)
        return min(first, last)...last
    }
    private var calendarDayCount: Int { (calendar.dateComponents([.day], from: calendar.startOfDay(for: calendarExtent.lowerBound), to: calendar.startOfDay(for: calendarExtent.upperBound)).day ?? 0) + 1 }
    private var calendarDays: [Date] {
        let offset = min(calendarPage * 14, max(0, calendarDayCount - 1))
        return (offset..<min(offset + 14, calendarDayCount)).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: calendarExtent.upperBound)) }
    }
    private func report(_ key: String) -> NapDayProjection {
        NapDayProjection(timeZoneID: zone, day: key, episodes: eligible.filter { $0.timeZoneID == zone }, review: document?.status(day: key, zone: zone, episodes: all) ?? .unreviewed)
    }
    private var selected: NapEpisode? { rows.first { $0.id == selectedNap && onInspectedDate($0) } }
    private var dayRows: [NapEpisode] { rows.filter { $0.day == day && $0.timeZoneID == zone } }
    private var projection: NapDayProjection {
        NapDayProjection(timeZoneID: zone, day: day, episodes: eligible.filter { $0.timeZoneID == zone },
            review: document?.status(day: day, zone: zone, episodes: all) ?? .unreviewed)
    }
    private var dayBounds: (Date, Date)? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = model.reportingTimeZone
        let start = cal.startOfDay(for: selectedDay)
        return cal.date(byAdding: .day, value: 1, to: start).map { (start, $0) }
    }
    private func onInspectedDate(_ row: NapEpisode) -> Bool {
        if row.timeZoneID == zone { return row.day == day }
        guard let source = NapPeriodEligibility.dayBounds(row), let bounds = dayBounds else { return false }
        return source.0 < bounds.1 && source.1 > bounds.0
    }
    var body: some View {
        List {
            Section("Sleep across the day") {
                DisclosureGroup("Sources and reporting rules") {
                Text("Main-night dates: " + model.rangeDescription).font(.caption)
                Text("Nap civil period: \(napWindow?.start.map { NapPeriodEligibility.stamp($0, zone: zone) } ?? "no history") to \(napWindow.map { NapPeriodEligibility.stamp($0.endExclusive, zone: zone) } ?? "unavailable") (end exclusive). Unknown starts on partial boundary dates cannot supply period estimates.").font(.caption)
                Text("Main-night filters use the dashboard's selected source: \(model.sleepSource.rawValue).").font(.caption)
                Text("Nap review as of \(NapPeriodEligibility.stamp(napAsOf, zone: zone)). Main provider history retains its dashboard query timestamp.").font(.caption)
                Text("Night dose-pattern/work filters apply to main sleep and available dose candidates. Independent nap records use the civil-date range; they have no inferred night association and are not filtered by night context.").font(.caption)
                Text("Naps retain their reviewed civil date inside the selected report dates. Main sleep keeps its treatment-session identity. These are separate measures, not a combined 24-hour total.").font(.caption)
                Text(model.healthQueryDescription).font(.caption)
                }
                if let issue = model.inspectionFilterIssue { Text(issue).foregroundStyle(.orange) }
                if let failure { Text(failure).foregroundStyle(.red) }
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
                DatePicker("Inspect calendar day", selection: Binding(get: { selectedDay }, set: { selectedDay = $0 }), in: ...max(napAsOf, selectedDay), displayedComponents: .date)
                if let id = selectedNap {
                    Text("Selected nap: " + id).font(.caption).accessibilityIdentifier("nap-selected-id")
                    let status = model.napInspection.selectionStatus(visibleIDs: rows.filter(onInspectedDate).map(\.id), knownIDs: all.map(\.id))
                    if let explanation = status.explanation { Text(explanation).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("nap-selection-status") }
                    Button("Clear nap selection") { selectedNap = nil }.accessibilityIdentifier("nap-clear-selection")
                }
                if let window = napWindow, let lower = window.start, let bounds = dayBounds, bounds.1 <= lower || bounds.0 >= window.endExclusive {
                    Text("The inspected date is outside the current reporting period. Its date and nap selection are retained.").font(.caption).foregroundStyle(.orange)
                }
                if let bounds = dayBounds {
                    Text("\(day) in \(zone): \(Int(bounds.1.timeIntervalSince(bounds.0) / 3600)) elapsed hours. DST calendar days are not always 24 hours.").font(.caption)
                }
            }
            DisclosureGroup("Calendar rows and daily values") {
                HStack {
                    Button("Newer days") { model.napInspection.setCalendarPage(max(0, calendarPage - 1)) }.disabled(calendarPage == 0)
                    Spacer()
                    Button("Older days") { model.napInspection.setCalendarPage(calendarPage + 1) }.disabled((calendarPage + 1) * 14 >= calendarDayCount)
                }
                if model.napInspection.calendarPage != calendarPage {
                    Text("The saved calendar page is outside this range. Showing the nearest page; the saved page is retained.").font(.caption)
                }
                ForEach(calendarDays, id: \.self) { date in
                    let key = NapEpisode.day(date, zone)
                    if let end = calendar.date(byAdding: .day, value: 1, to: date) {
                        let daily = report(key)
                        VStack(alignment: .leading) {
                            Button("Review " + key) { selectedDay = min(max(date, calendarExtent.lowerBound), calendarExtent.upperBound) }
                            Text("\(daily.completenessLabel) · \(daily.episodeCount) episode records · \(daily.unavailableCount) estimates unavailable").font(.caption)
                            clockRows((date, end), projection: daily)
                        }
                    }
                }
                Text("Fourteen calendar dates per page; daily record counts and estimates retain the reviewed episode date. Unknown-time records remain in the exact table.").font(.caption)
            }
            Section("Nap completeness and reported duration") {
                Text(projection.completenessLabel).font(.headline)
                Text("\(projection.episodeCount) episode records • \(projection.unavailableCount) estimates unavailable or needing review")
                Text(projection.estimatedMinutes.map { String(format: "%.1f minutes reported asleep", $0) } ?? "Reported asleep duration unavailable")
                Text("These are dated record counts, not proof every record falls within exact period bounds. Estimates are assigned once by known start, or by a fully covered recorded date when start is unknown; whole-episode estimates are not prorated. Partial reports do not describe the whole day.").font(.caption)
                if projection.reviewConflict { Text("No-naps confirmation conflicts with recorded episodes. Review these records.").foregroundStyle(.orange) }
                if !projection.unresolvedDuplicateIDs.isEmpty { Text("Some episode links or duplicate source records need review. Their estimates are excluded from duration totals.").foregroundStyle(.orange) }
                if !projection.overlapIDs.isEmpty { Text("Overlapping episodes are excluded from duration totals until explicitly reconciled. Review both records; overlap is not proof they are the same nap.").foregroundStyle(.orange) }
                Picker("Review this calendar day", selection: $completeness) {
                    Text("Choose after review").tag(NapCompleteness?.none)
                    ForEach(NapCompleteness.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Button("Save day review", action: saveDay).disabled(document == nil || completeness == nil)
            }
            Section("Exact nap records") {
                if dayRows.isEmpty { Text("No nap record saved for this date in \(zone). That does not establish no naps.") }
                ForEach(dayRows) { row in
                    Button { selectedNap = row.id; napCheck.invalidate() } label: {
                        VStack(alignment: .leading) {
                            Text(row.intent.rawValue + " · " + row.id.suffix(6)).font(.headline)
                            Text(row.start.map { NapPeriodEligibility.stamp($0, zone: row.timeZoneID) } ?? "Clock start unknown")
                            Text(row.end.map { "Ended \(NapPeriodEligibility.stamp($0, zone: row.timeZoneID))" } ?? "End unknown / duration only")
                            Text("Rest: \(minutes(row.restMinutes)); estimated asleep: \(minutes(row.estimatedSleepMinutes))")
                            Text(row.benefitRating.map { "Custom benefit: \($0)/10" } ?? "Benefit not reported")
                            if let duplicate = row.duplicateOf { Text("Linked to same episode: " + duplicate.suffix(6)) }
                            if projection.unresolvedDuplicateIDs.contains(row.id) { Text("Episode match needs review") }
                            if row.sourceNeedsReview { Text("Recorded timer evidence changed; review this episode again.") }
                            if let reason = NapPeriodEligibility.exclusion(row, in: napWindow) { Text(reason) }
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("nap-record-" + row.id)
                }
                if let selected {
                    Button("Review selected nap") { editing = selected }.disabled(document == nil)
                    providerPanel(selected)
                    let selectedProjection = NapDayProjection(timeZoneID: selected.timeZoneID, day: selected.day, episodes: eligible.filter { $0.timeZoneID == selected.timeZoneID }, review: document?.status(day: selected.day, zone: selected.timeZoneID, episodes: all) ?? .unreviewed)
                    if selectedProjection.overlapIDs.contains(selected.id) || selectedProjection.unresolvedDuplicateIDs.contains(selected.id) {
                        Text("Resolve overlapping or conflicting episode observations before comparing a nap-end interval.").font(.caption)
                    } else { NapDoseComparisonView(episode: selected, nights: model.visibleInspectionNights, asOf: napAsOf, doseDataAsOf: model.reportingAsOf) }
                }
                let otherZones = rows.filter { $0.timeZoneID != zone && onInspectedDate($0) }
                if !otherZones.isEmpty {
                    Text("\(otherZones.count) records have original calendar dates in another timezone that overlap this inspection date. They remain separate from this date's totals and retain original dates in the export.").font(.caption)
                    ForEach(otherZones) { row in Button("\(row.day) · \(row.timeZoneID) · \(row.id.suffix(6))") { selectedNap = row.id; napCheck.invalidate() }.accessibilityIdentifier("nap-record-" + row.id) }
                }
            }
            Section("Main sleep and reviewed coverage") {
                Text("Primary-episode totals remain separate from a checked reviewed-night window and from nap reports.").font(.caption)
                Picker("Main session", selection: Binding(get: { selectedMain }, set: { model.inspection.selectedObservationID = $0 })) {
                    Text("Choose a session").tag(String?.none)
                    if let selectedMain, !model.visibleInspectionNights.contains(where: { $0.id == selectedMain }) {
                        Text("Selected observation is filtered or unavailable").tag(Optional(selectedMain))
                    }
                    ForEach(model.visibleInspectionNights) { night in Text(night.sessionDate + " · " + night.id.suffix(6)).tag(Optional(night.id)) }
                }
                if let id = selectedMain, let night = model.visibleInspectionNights.first(where: { $0.id == id }) {
                    Text("Apple Health primary episode: \(minutes(night.appleHealthSleepMinutes)); WHOOP primary episode: \(minutes(night.whoopSleepMinutes))")
                    Text("Observed Apple Health sleep after Dose 2: \(minutes(night.postDoseSleep?.asleepMinutes)). Without a usable Dose 2 occurrence this is unavailable, not total sleep.").font(.caption)
                    Button("Check reviewed main-sleep window") {
                        guard let rawSessionID = night.sessionID, !night.identityNeedsReview else { return }
                        Task { await mainCheck.refresh(sessionDate: night.sessionDate) { _ in
                            await model.dashboardReviewedCoverage(sessionID: rawSessionID)
                        } }
                    }.disabled(mainCheck.isLoading || night.sessionID == nil || night.identityNeedsReview)
                    if let result = mainCheck.result {
                        Text(result.explanation)
                        if let value = result.projection {
                            Text("Reviewed window asleep \(minutes(value.coverage.asleepMinutes)), awake \(minutes(value.coverage.awakeMinutes)), unmeasured \(minutes(value.coverage.unmeasuredMinutes))")
                            Text("Conflict \(minutes(value.conflictMinutes)) is already included in unmeasured.").font(.caption)
                        }
                    }
                }
            }
            Section("Share reviewed values") {
                Button("Preview nap comparison CSV") { exportText = csv }.disabled(document == nil)
                Text("Original record IDs, date/timezone, estimates, rest duration, missingness, completeness and snapshot time are included. Free-text reasons are excluded.").font(.caption)
            }
        }.navigationTitle("Sleep & Naps").environment(\.timeZone, model.reportingTimeZone)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add nap report") { adding = true }.disabled(document == nil).accessibilityIdentifier("nap-add-report") } }
            .task { load(); model.napInspection.initializeDayIfNeeded(calendarExtent.upperBound) }
            .refreshable { await model.refreshAndWait(); load() }
            .onChange(of: selectedDay) { _ in completeness = nil; napCheck.invalidate(); exportText = nil }
            .onChange(of: model.napInspection) { _ in napCheck.invalidate(); exportText = nil }
            .onDisappear { napCheck.invalidate(); mainCheck.invalidate(); exportText = nil }
            .onChange(of: model.inspection) { _ in mainCheck.invalidate() }
            .onChange(of: model.currentReportWindow) { _ in
                completeness = nil; napCheck.invalidate(); mainCheck.invalidate(); exportText = nil
            }
            .onChange(of: model.reportingTimeZone) { _ in load() }
            .onReceive(model.sessionRepo.sessionDidChange) { _ in napCheck.invalidate(); mainCheck.invalidate(); load() }
            .onReceive(model.providerAccess.changes) { _ in napCheck.invalidate(); mainCheck.invalidate(); exportText = nil }
            .onReceive(model.$nights) { _ in napCheck.invalidate(); mainCheck.invalidate(); exportText = nil }
            .sheet(isPresented: $adding) { NapEpisodeEditor(original: nil, candidates: all, source: nil, day: day, zone: zone, save: saveEpisode) }
            .sheet(item: $editing) { row in NapEpisodeEditor(original: row, candidates: all, source: timers.first { $0.id == row.id }, persistedRevision: document?.episodes.contains { $0.revision == row.revision } == true ? row.revision : nil, day: row.day, zone: row.timeZoneID, save: saveEpisode) }
            .sheet(isPresented: Binding(get: { exportText != nil }, set: { if !$0 { exportText = nil } })) {
                NavigationStack { ScrollView { VStack { Text(exportText ?? "").font(.caption.monospaced()).accessibilityIdentifier("nap-export-csv"); ShareLink("Share CSV text", item: exportText ?? "") }.padding() }
                    .navigationTitle("Nap export preview").toolbar { Button("Close") { exportText = nil } } }
            }
    }
    private func minutes(_ value: Double?) -> String { value.map { String(format: "%.1f min", $0) } ?? "unavailable" }
    @ViewBuilder private func clockRows(_ civilBounds: (Date, Date), projection: NapDayProjection) -> some View {
        let bounds = (max(civilBounds.0, napWindow?.start ?? civilBounds.0), min(civilBounds.1, napWindow?.endExclusive ?? civilBounds.1))
        let naps = all.filter { $0.start != nil && $0.end != nil && $0.start! < bounds.1 && $0.end! > bounds.0 && $0.duplicateOf == nil }
        let main = model.visibleInspectionNights.flatMap { $0.healthSummary?.recordedIntervals ?? [] }
            .filter { $0.start < bounds.1 && $0.end > bounds.0 }
        Chart {
            ForEach(model.visibleInspectionNights) { night in
                if let summary = night.healthSummary, let lower = summary.sleepOnset ?? summary.bedTime,
                   let upper = summary.finalWake ?? summary.observationEnd, lower < upper, lower < bounds.1, upper > bounds.0 {
                    BarMark(xStart: .value("Start", max(bounds.0, lower)), xEnd: .value("End", min(bounds.1, upper)), y: .value("Observation", "Apple Health episode bounds"))
                        .foregroundStyle(.blue)
                }
            }
            ForEach(naps) { nap in
                BarMark(xStart: .value("Start", max(bounds.0, nap.start!)), xEnd: .value("End", min(bounds.1, nap.end!)), y: .value("Observation", "Nap/rest window"))
                    .foregroundStyle(.orange)
            }
        }.chartXScale(domain: bounds.0...bounds.1).chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in AxisGridLine(); AxisValueLabel(format: Date.FormatStyle(date: .omitted, time: .shortened, calendar: Calendar(identifier: .gregorian), timeZone: model.reportingTimeZone)) } }
            .frame(height: 150)
            .accessibilityLabel("Primary episode bounds and nap rest windows on the selected local-day clock. Separate rows identify observation types. Exact nap values follow.")
        ForEach(naps) { nap in
            Text("Nap/rest \(nap.id): \(NapPeriodEligibility.stamp(nap.start!, zone: nap.timeZoneID)) – \(NapPeriodEligibility.stamp(nap.end!, zone: nap.timeZoneID)); original date \(nap.day), \(nap.timeZoneID)." + (nap.sourceNeedsReview ? " Source changed; review required." : "")).font(.caption).textSelection(.enabled)
        }
        Text("Blue: Apple Health primary-episode bounds. Orange: reported nap/rest window. Neither span means continuously asleep; checked coverage below supplies resolved asleep/awake/unknown accounting. Duration-only and incomplete naps have no invented bar. Cross-midnight bars are clipped; records retain their original episode date.").font(.caption)
        let measured = main.isEmpty ? nil : SleepIntervalCoverage.calculate(start: bounds.0, end: bounds.1, intervals: main)?.asleepMinutes
        Chart {
            if let measured { BarMark(x: .value("Measure", "Apple Health primary sleep"), y: .value("Minutes", measured)).foregroundStyle(.blue) }
            ForEach(NapIntent.allCases, id: \.self) { intent in
                if let estimated = projection.estimatedMinutesByIntent[intent] { BarMark(x: .value("Measure", intent.rawValue), y: .value("Minutes", estimated)).foregroundStyle(.orange) }
            }
        }.frame(height: 130)
        ForEach(NapIntent.allCases, id: \.self) { intent in Text("\(intent.rawValue): \(minutes(projection.estimatedMinutesByIntent[intent])) reported asleep").font(.caption) }
        Text("Apple Health primary-episode asleep intervals on this day: \(minutes(measured)). Reported nap estimates: \(minutes(projection.estimatedMinutes)). Separate bars are not additive: main coverage may be partial and nap estimates have a different source.").font(.caption)
    }
    @ViewBuilder private func providerPanel(_ episode: NapEpisode) -> some View {
        let reviewed = document?.current.contains { $0.id == episode.id } == true
        Button("Check Apple Health for selected nap") {
            let access = model.providerAccess.revision
            Task { await napCheck.check(episode: episode, clock: Date.init, current: {
                let doc = try model.sessionRepo.napDiary()
                let source = try model.sessionRepo.napTimerEpisodes(asOf: Date(), timeZoneID: episode.timeZoneID)
                return doc?.merging(source).first { $0.id == episode.id }
            }, allowed: { model.settings.healthKitEnabled && model.providerAccess.revision == access },
                query: { try await model.healthKit.fetchSleepEvidence(from: $0, to: $1) }) }
        }.disabled(!reviewed || episode.sourceNeedsReview || episode.start == nil || episode.end == nil || episode.duplicateOf != nil || napCheck.busy)
        Text(napCheck.message).font(.caption)
        if let evidence = napCheck.evidence {
            Text("Provider-observed asleep \(minutes(evidence.coverage.asleepMinutes)); awake \(minutes(evidence.coverage.awakeMinutes)); unmeasured \(minutes(evidence.coverage.unmeasuredMinutes))")
            Text("Same episode \(episode.id). Provider result is compared with your estimate, never added as a second nap. Checked \(napCheck.checkedAt.map { NapPeriodEligibility.stamp($0, zone: zone) } ?? "unavailable"). Conflicts remain unmeasured.").font(.caption)
        }
    }
    private func load() {
        napCheck.invalidate(); mainCheck.invalidate(); exportText = nil
        do {
            let saved = try model.sessionRepo.napDiary()
            let captured = Date()
            timers = try model.sessionRepo.napDiarySources(document: saved, asOf: captured, defaultTimeZoneID: zone)
            napAsOf = captured
            document = saved ?? NapDiaryDocument(); storedRevision = saved?.revision; failure = nil
        } catch { document = nil; timers = []; failure = error.localizedDescription }
    }
    private func saveEpisode(_ value: NapEpisode) throws {
        guard var next = document else { throw NapDiaryStorageError.unreadable }
        if !value.sourceEventIDs.isEmpty {
            let currentSource = try model.sessionRepo.napTimerEpisodes(asOf: Date(), timeZoneID: value.timeZoneID).filter { $0.id == value.id }
            guard currentSource.count == 1, currentSource.first?.evidenceKey == value.sourceEvidenceKey else { throw NapDiaryStorageError.stale }
        }
        guard next.current.first(where: { $0.id == value.id })?.revision == value.predecessor else { throw NapDiaryStorageError.stale }
        next.episodes.append(value); next.revision = UUID()
        try model.sessionRepo.saveNapDiary(next, expectedRevision: storedRevision)
        document = next; storedRevision = next.revision; napCheck.invalidate()
    }
    private func saveDay() {
        guard var next = document, let completeness else { return }
        next.reviews.append(.init(day: day, timeZoneID: zone, status: completeness, recordedAt: Date(), episodes: all))
        next.revision = UUID()
        do { try model.sessionRepo.saveNapDiary(next, expectedRevision: storedRevision); document = next; storedRevision = next.revision; self.completeness = nil }
        catch { failure = error.localizedDescription }
    }
    private var csv: String {
        let headers = ["record_kind", "episode_id", "calendar_date", "timezone", "start_utc", "end_utc", "rest_minutes", "reported_asleep_minutes", "eligible_reported_asleep_minutes", "intent", "custom_benefit_0_to_10", "same_episode_as", "day_completeness", "episode_count", "unavailable_count", "review_conflict", "exclusion_reason", "source_event_ids", "provider_source", "provider_observed_asleep_minutes", "provider_unmeasured_minutes", "provider_checked_at", "snapshot_at", "definition", "export_scope", "inspection_date", "period_start_utc", "period_end_exclusive_utc", "period_as_of_utc", "period_timezone", "night_filter_policy", "main_source_policy"]
        let stamp = ISO8601DateFormatter(), window = napWindow
        let metadata = ["export_scope": "selected_inspection_day_and_boundary_clock_spans", "inspection_date": day, "period_start_utc": window?.start.map(stamp.string(from:)) ?? "", "period_end_exclusive_utc": window.map { stamp.string(from: $0.endExclusive) } ?? "",
            "period_as_of_utc": stamp.string(from: model.reportingAsOf), "period_timezone": zone, "night_filter_policy": "not_applied_to_independent_naps_without_explicit_association", "main_source_policy": model.sleepSource.rawValue]
        func line(_ values: [String: String]) -> String { ReportCSV.row(headers.map { values[$0] ?? metadata[$0] ?? "" }) }
        let selectedDates = rows.filter(onInspectedDate)
        let groups = Set(selectedDates.map { $0.timeZoneID + "|" + $0.day } + [zone + "|" + day]).sorted()
        var output = [ReportCSV.row(headers)]
        for group in groups {
            let parts = group.split(separator: "|"), originalZone = String(parts[0]), originalDay = String(parts[1])
            let report = NapDayProjection(timeZoneID: originalZone, day: originalDay, episodes: eligible.filter { $0.timeZoneID == originalZone }, review: document?.status(day: originalDay, zone: originalZone, episodes: all) ?? .unreviewed)
            output.append(line(["record_kind": "day_summary", "calendar_date": originalDay, "timezone": originalZone,
                "eligible_reported_asleep_minutes": report.estimatedMinutes.map(String.init(describing:)) ?? "",
                "day_completeness": report.completenessLabel, "episode_count": String(report.episodeCount), "unavailable_count": String(report.unavailableCount),
                "review_conflict": String(report.reviewConflict), "snapshot_at": stamp.string(from: napAsOf),
                "exclusion_reason": report.episodes.isEmpty && report.review == .unreviewed ? "No nap records or day review collected" : "",
                "definition": "nap_review_v1; start-date allocation; reported estimates are not provider sleep"]))
            for row in selectedDates.filter({ $0.timeZoneID == originalZone && $0.day == originalDay }) {
                let periodReason = NapPeriodEligibility.exclusion(row, in: window)
                let excluded = periodReason != nil || row.sourceNeedsReview || report.overlapIDs.contains(row.id) || report.unresolvedDuplicateIDs.contains(row.id)
                let retained = report.episodes.contains { $0.id == row.id }
                var fields: [String: String] = ["record_kind": "episode", "episode_id": row.id, "calendar_date": row.day, "timezone": row.timeZoneID,
                    "start_utc": row.start.map(stamp.string(from:)) ?? "", "end_utc": row.end.map(stamp.string(from:)) ?? "",
                    "rest_minutes": row.restMinutes.map(String.init(describing:)) ?? "", "reported_asleep_minutes": row.estimatedSleepMinutes.map(String.init(describing:)) ?? "",
                    "eligible_reported_asleep_minutes": !excluded && retained ? row.estimatedSleepMinutes.map(String.init(describing:)) ?? "" : "",
                    "intent": row.intent.rawValue, "custom_benefit_0_to_10": row.benefitRating.map(String.init) ?? "", "same_episode_as": row.duplicateOf ?? "",
                    "day_completeness": report.completenessLabel, "exclusion_reason": periodReason ?? (excluded ? "Source change, overlap or episode association needs review" : (!retained ? "Explicit same-episode link; not counted again" : (row.estimatedSleepMinutes == nil ? "No asleep estimate" : ""))),
                    "source_event_ids": row.sourceEventIDs.joined(separator: ";"), "snapshot_at": stamp.string(from: napAsOf), "definition": "nap_review_v1"]
                if row.id == selectedNap, let evidence = napCheck.evidence {
                    fields["provider_source"] = "Apple Health"
                    fields["provider_observed_asleep_minutes"] = evidence.coverage.asleepMinutes.map(String.init(describing:)) ?? ""
                    fields["provider_unmeasured_minutes"] = String(evidence.coverage.unmeasuredMinutes)
                    fields["provider_checked_at"] = napCheck.checkedAt.map(stamp.string(from:)) ?? ""
                }
                output.append(line(fields))
            }
        }
        if let civil = dayBounds, let window = napWindow, let lower = window.start {
            let bounds = (max(civil.0, lower), min(civil.1, window.endExclusive)); for row in all where row.day != day && row.duplicateOf == nil {
                if let start = row.start, let end = row.end, bounds.0 < bounds.1, start < bounds.1, end > bounds.0 {
                    output.append(line(["record_kind": "boundary_clock_span", "episode_id": row.id, "calendar_date": row.day, "timezone": row.timeZoneID,
                        "start_utc": stamp.string(from: max(start, bounds.0)), "end_utc": stamp.string(from: min(end, bounds.1)),
                        "exclusion_reason": "Clipped clock span only; episode count and estimate belong to its original date" + (row.sourceNeedsReview ? "; source needs review" : ""), "snapshot_at": stamp.string(from: napAsOf), "definition": "nap_review_v1; no prorated asleep estimate"]))
                }
            }
        }
        return output.joined(separator: "\r\n") + "\r\n"
    }
}
