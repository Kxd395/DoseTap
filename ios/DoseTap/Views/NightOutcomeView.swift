import SwiftUI
import DoseCore

extension Dose2WakeKind {
    var title: String { rawValue.capitalized }
}
extension FollowingDayKind {
    var title: String { self == .dayOff ? "Day off" : rawValue.capitalized }
}

private extension ReviewedWindowAssessment.Reason {
    var explanation: String {
        switch self {
        case .invalidWindow: return "A saved window's dates or identity need review."
        case .invalidDoseRecords: return "The dose records have conflicting or invalid timing."
        case .doseOutsideWindow: return "A recorded dose is outside these bounds."
        case .overlappingWindow: return "Another reviewed night overlaps this window."
        case .overlappingNap: return "A recorded nap overlaps this window."
        case .incompleteNap: return "A nap with a missing start or end could overlap this window."
        case .ambiguousNap: return "Overlapping or equal-time nap markers need review."
        case .unreadableEvidence: return "Some records could not be read. No missing time was filled in."
        }
    }
}

/// Local selection only. The enclosing dose confirmation owns the eventual write.
struct Dose2WakeSelection: View {
    @Binding var selection: Dose2WakeKind
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How did you wake for Dose 2?").font(.headline)
            HStack(spacing: 12) {
                option(.natural, "Woke naturally")
                option(.alarm, "Woke to an alarm")
            }
            Text("Optional. Leave both unchecked if unsure; you can add or correct this in the morning.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func option(_ kind: Dose2WakeKind, _ title: String) -> some View {
        Button { selection = selection == kind ? .unknown : kind } label: {
            Label(title, systemImage: selection == kind ? "checkmark.square.fill" : "square")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("dose2-wake-\(kind.rawValue)")
        .accessibilityValue(selection == kind ? "Selected" : "Not selected")
    }
}

/// Review the same wake answer later without changing the medication record.
struct NightOutcomeButton: View {
    let sessionDate: String
    var accessibilityID: String = "night-outcome-open"
    @State private var showing = false
    @State private var summary = "Natural / Alarm · Next-day check-in"
    private let repo = SessionRepository.shared
    var body: some View {
        Button { showing = true } label: {
            Label(summary, systemImage: "sun.and.horizon")
                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier(accessibilityID)
        .sheet(isPresented: $showing, onDismiss: load) { NightOutcomeEditor(sessionDate: sessionDate) }
        .task(id: sessionDate) { load() }
        .onReceive(repo.sessionDidChange) { load() }
    }
    private func load() {
        if let answers = try? repo.nightOutcomeSnapshot(sessionDate: sessionDate).record?.answers {
            summary = "Dose 2 wake: \(answers.wakeMethod.title) · Next-day check-in"
        } else { summary = "Natural / Alarm · Next-day check-in" }
    }
}

struct NightOutcomeEditor: View {
    let sessionDate: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthkit_enabled") private var healthKitEnabled = false
    @State private var coverageRequest: UUID?
    @State private var coverageResult: ReviewedNightSleepResult?
    @State private var review: NightOutcomeSnapshot?
    @State private var answers = NightOutcomeDiary()
    @State private var finalWake = Date()
    @State private var assessedAt = Date()
    @State private var hasFinalWake = false
    @State private var hasSleepiness = false
    @State private var rating = 5
    @State private var reason = ""
    @State private var error: String?
    @State private var saved = false
    @State private var showSaveError = false
    @State private var windowEnabled = false
    @State private var windowStart = Date()
    @State private var windowEnd = Date()
    @State private var windowReviewedAt = Date()
    @State private var windowConfirmed = false
    @State private var windowZone = TimeZone.current
    @State private var windowAssessment: ReviewedWindowAssessment?
    private let repo = SessionRepository.shared

    private var windowUnchanged: Bool {
        guard let old = answers.reviewedSleepWindow else { return false }
        return windowEnabled && windowStart == old.start && windowEnd == old.end
    }
    private var windowDraft: ReviewedSleepWindow? {
        guard windowEnabled, let review else { return nil }
        if windowUnchanged { return answers.reviewedSleepWindow }
        return .init(sessionID: review.history.sessionId, start: windowStart, end: windowEnd,
                     entryTimeZone: windowZone, reviewedAt: windowReviewedAt)
    }
    private var draft: NightOutcomeDiary {
        var value = answers
        value.finalWakeAt = hasFinalWake ? finalWake : nil
        value.sleepiness = hasSleepiness ? rating : nil
        value.assessedAt = hasSleepiness ? assessedAt : nil
        value.reviewedSleepWindow = windowDraft
        return value
    }
    private var needsReason: Bool { review?.record.map { draft.changesAnsweredFields(of: $0.answers) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Treatment night: \(sessionDate)")
                    Text("These answers do not record a dose or change alarms.").font(.footnote)
                }
                if needsReason {
                    Section("Reason required for correction") {
                        TextField("Why are you changing this answer?", text: $reason, axis: .vertical)
                            .accessibilityIdentifier("night-outcome-reason")
                        Text("Prior answers are retained. Adding an unanswered field does not need a correction reason.").font(.footnote)
                    }
                }
                Section("Wake method for Dose 2") {
                    Picker("Wake method", selection: $answers.wakeMethod) {
                        ForEach(Dose2WakeKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("night-wake-method")
                    .disabled(review?.history.events.contains(where: { $0.eventType == "dose2" }) != true)
                    Picker("Backup alarm set", selection: $answers.backupAlarmSet) {
                        Text("Unknown").tag(nil as Bool?)
                        Text("Yes").tag(true as Bool?)
                        Text("No").tag(false as Bool?)
                    }
                    Text("Waking naturally before a backup alarm still counts as Natural.").font(.footnote)
                }
                Section("Following day") {
                    Picker("Day type", selection: $answers.dayType) {
                        ForEach(FollowingDayKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Workday or day off refers to the day after this treatment night.").font(.footnote)
                    Toggle("Record final awakening", isOn: $hasFinalWake)
                    if hasFinalWake {
                        DatePicker("Final awakening", selection: $finalWake, in: ...Date())
                    }
                    Toggle("Record next-day sleepiness", isOn: $hasSleepiness)
                        .accessibilityIdentifier("night-sleepiness-toggle")
                    if hasSleepiness {
                        Stepper("Sleepiness: \(rating) / 10", value: $rating, in: 0...10)
                        DatePicker("Assessed at", selection: $assessedAt, in: ...Date())
                        Text("0 = fully alert; 10 = struggling to stay awake. Record final awakening too. Aim for a consistent time, such as six hours after final awakening. This is a personal diary rating, not a validated clinical score.")
                            .font(.footnote)
                    }
                }
                windowSection
                if let error {
                    Section("Not saved") {
                        Text(error).foregroundStyle(.red)
                        Button("Reload saved answers") { load() }
                    }
                }
                if let revisions = review?.record?.revisions, !revisions.isEmpty {
                    DisclosureGroup("Previous answers (\(revisions.count))") {
                        ForEach(Array(revisions.enumerated()), id: \.offset) { _, revision in
                            Text("\(revision.recordedAt.formatted()): \(revision.answers.wakeMethod.title), sleepiness \(revision.answers.sleepiness.map(String.init) ?? "not recorded"). \(revision.reason)")
                                .font(.footnote)
                            if let window = revision.answers.reviewedSleepWindow {
                                Text(windowDescription(window)).font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wake & Next Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(review == nil)
                        .accessibilityIdentifier("night-outcome-save")
                }
            }
            .onAppear { load() }
            .onReceive(repo.sessionDidChange) { clearCoverage(); refreshAssessment() }
            .onChange(of: windowStart) { _ in clearCoverage() }
            .onChange(of: windowEnd) { _ in clearCoverage() }
            .onChange(of: windowEnabled) { _ in clearCoverage() }
            .onChange(of: healthKitEnabled) { _ in clearCoverage() }
            .onChange(of: scenePhase) { if $0 != .active { clearCoverage() } }
            .onDisappear { clearCoverage() }
            .task(id: coverageRequest) {
                guard let request = coverageRequest, windowUnchanged else { return }
                let result = await repo.reviewedNightSleep(sessionDate: sessionDate)
                guard !Task.isCancelled, coverageRequest == request, windowUnchanged else { return }
                coverageResult = result
            }
            .alert("Answers saved", isPresented: $saved) { Button("OK") { dismiss() } }
            .alert("Answers not saved", isPresented: $showSaveError) { Button("OK", role: .cancel) {} } message: {
                Text(error ?? "Please review the answers and try again.")
            }
        }
    }
    private var windowSection: some View {
        Section("Night window (optional)") {
            Toggle("Save a reviewed window", isOn: $windowEnabled)
                .accessibilityIdentifier("night-window-enabled")
                .onChange(of: windowEnabled) { _ in windowConfirmed = false }
            Text("Choose the start and end of the night you want to review. This range is not measured sleep or a final-awakening answer. Existing charts and totals are unchanged for now.")
                .font(.footnote)
            if windowEnabled {
                DatePicker("Window start", selection: $windowStart, in: ...Date())
                    .accessibilityIdentifier("night-window-start")
                    .onChange(of: windowStart) { _ in windowConfirmed = false }
                DatePicker("Window end", selection: $windowEnd, in: ...Date())
                    .accessibilityIdentifier("night-window-end")
                    .onChange(of: windowEnd) { _ in windowConfirmed = false }
                Text("Dates shown in \(windowZone.identifier). Suggested dates must be reviewed before saving.")
                    .font(.footnote)
                if let value = windowDraft {
                    Text(windowDescription(value)).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("night-window-range")
                }
                if windowUnchanged {
                    Text("Saved reviewed window").accessibilityIdentifier("night-window-saved")
                    if let assessment = windowAssessment {
                        Text(assessment.status == .checked ? "Saved bounds checked" : "Saved bounds need review")
                            .font(.subheadline).accessibilityIdentifier("night-window-assessment")
                        ForEach(assessment.reasons, id: \.self) { Text($0.explanation).font(.footnote) }
                        Text("Checks cover local dose, night-window and nap records. They do not confirm measured sleep. Charts and totals are unchanged.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Recheck saved bounds") { clearCoverage(); refreshAssessment() }
                        if assessment.status == .checked {
                            Button("Check Apple Health coverage") { coverageResult = nil; coverageRequest = UUID() }
                                .accessibilityIdentifier("night-window-check-coverage")
                                .disabled(coverageRequest != nil && coverageResult == nil)
                            if coverageRequest != nil && coverageResult == nil { ProgressView("Checking coverage...") }
                            if let result = coverageResult { ReviewedNightCoverageView(result: result) }
                        }
                    } else {
                        Button("Reload changed saved answers") { load() }
                    }
                } else {
                    Toggle("I reviewed both dates and times", isOn: $windowConfirmed)
                        .accessibilityIdentifier("night-window-confirm")
                        .onChange(of: windowConfirmed) { confirmed in
                            if confirmed { windowReviewedAt = Date() }
                        }
                }
            }
        }
        .environment(\.timeZone, windowZone)
    }
    private func windowDescription(_ value: ReviewedSleepWindow) -> String {
        let formatter = ISO8601DateFormatter()
        return "UTC: \(formatter.string(from: value.start)) to \(formatter.string(from: value.end))"
    }
    private func load() {
        clearCoverage()
        do {
            let snapshot = try repo.nightOutcomeSnapshot(sessionDate: sessionDate)
            guard !snapshot.history.isNew else { error = "Add this night's dose or questionnaire record first."; review = nil; return }
            review = snapshot; answers = snapshot.record?.answers ?? NightOutcomeDiary()
            hasFinalWake = answers.finalWakeAt != nil; hasSleepiness = answers.sleepiness != nil
            finalWake = answers.finalWakeAt ?? Date(); assessedAt = answers.assessedAt ?? Date()
            rating = answers.sleepiness ?? 5; reason = ""; error = nil
            let window = answers.reviewedSleepWindow
            windowEnabled = window != nil
            windowStart = window?.start ?? snapshot.history.events.first(where: { $0.eventType == "dose1" })?.timestamp ?? Date()
            windowEnd = window?.end ?? answers.finalWakeAt ?? windowStart
            windowZone = window.flatMap { TimeZone(identifier: $0.entryTimeZoneID) } ?? .current
            windowReviewedAt = window?.reviewedAt ?? Date(); windowConfirmed = false
            refreshAssessment()
        } catch { self.error = "This night's answers could not be read. Nothing has changed."; review = nil }
    }
    private func refreshAssessment() {
        guard let current = try? repo.nightOutcomeSnapshot(sessionDate: sessionDate),
              current.record?.answers.reviewedSleepWindow == answers.reviewedSleepWindow else {
            windowAssessment = nil; return
        }
        windowAssessment = repo.reviewedWindowAssessment(sessionDate: sessionDate)
    }
    private func clearCoverage() { coverageRequest = nil; coverageResult = nil }
    private func save() {
        guard let review else { return }
        if windowEnabled && !windowUnchanged && !windowConfirmed {
            error = "Review both window dates and times, then confirm them before saving."
            showSaveError = true; return
        }
        let result = repo.saveNightOutcome(draft, review: review, reason: reason)
        if result.isCommitted { error = nil; saved = true }
        else { error = result.failure?.detail ?? "Answers were not saved. Please reload and review."; showSaveError = true }
    }
}

struct ReviewedNightCoverageView: View {
    let result: ReviewedNightSleepResult
    private func minutes(_ value: Double?) -> String { value.map { String(format: "%.1f min", $0) } ?? "Not observed" }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.explanation).accessibilityIdentifier("night-window-coverage-status")
            if let evidence = result.evidence {
                Text("Estimated sleep: \(minutes(evidence.coverage.asleepMinutes))")
                Text("Recorded awake: \(minutes(evidence.coverage.awakeMinutes))")
                Text("Unmeasured: \(minutes(evidence.coverage.unmeasuredMinutes))")
                if evidence.conflictMinutes > 0 { Text("Conflicting: \(minutes(evidence.conflictMinutes)), included in unmeasured time") }
                if let checkedAt = result.checkedAt { Text("Checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))") }
                Text("Apple Health estimates within your reviewed bounds. Check again for later imports or edits. Existing charts and exports are unchanged.")
                    .foregroundStyle(.secondary)
            }
        }.font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
}
