import SwiftUI
import DoseCore

struct TonightDaytimeCheckInCard: View {
    @State private var recording = false
    @State private var savedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Daytime check-in", systemImage: "sun.max")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Record how sleepy you feel now, when it is safe to pause. Details are optional.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { recording = true } label: {
                Text("Record now")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Record daytime check-in now")
            .accessibilityIdentifier("tonight-daytime-record")
            if let savedAt {
                Label("Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .accessibilityIdentifier("tonight-daytime-saved")
            }
            NavigationLink { DaytimeCheckInView() } label: {
                Label("Review check-ins", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("tonight-daytime-review")
            NavigationLink { DaytimeReminderView() } label: {
                Label("Daytime reminder", systemImage: "bell")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("tonight-daytime-reminder")
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $recording) {
            DaytimeCheckInEditor { observation in savedAt = observation.recordedAt }
        }
    }
}

struct DaytimeCheckInView: View {
    @ObservedObject private var repository = SessionRepository.shared
    @State private var ledger: DaytimeCheckInLedger?
    @State private var failure: String?
    @State private var adding = false
    @State private var editing: DaytimeCheckIn?
    var body: some View {
        List {
            Section {
                Text("Record only when it is safe to pause. This custom diary records your experience; saving does not notify a clinician.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Daytime trends") { DaytimeTrendsView() }
                NavigationLink("Daytime events") { DaytimeEventView() }
                NavigationLink("Daytime reminder") { DaytimeReminderView() }
                    .accessibilityIdentifier("daytime-reminder-settings")
                Button("Record daytime check-in") { adding = true }
                    .disabled(ledger == nil).accessibilityIdentifier("daytime-add")
            }
            if let failure {
                Section { Text(failure); Button("Retry loading", action: reload) }
            }
            if let ledger {
                if ledger.current.isEmpty { Text("No daytime observations recorded. Missing observations are not zero sleepiness.") }
                ForEach(ledger.current) { value in
                    Section {
                        Text(value.assessedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline).accessibilityIdentifier("daytime-saved-observation-\(value.id.uuidString)")
                        Text(value.response.map { "Custom sleepiness: \($0)/10" } ?? "Response: \(value.status.rawValue)")
                        Text(value.origin.title)
                        if let activity = value.activity { Text(activity.rawValue) }
                        Text("Setting: \(value.setting.rawValue). Coping: \(value.coping.rawValue)")
                        if !value.copingActions.isEmpty { Text(value.copingActions.map(\.rawValue).joined(separator: ", ")) }
                        if !value.note.isEmpty { Text(value.note) }
                        if let review = value.eventReview { Text("Event review: \(review.from.formatted()) – \(review.to.formatted()); \(review.status.rawValue), \(review.eventIDs.count) linked events") }
                        if let links = value.sourceLinks, !links.isEmpty {
                            DisclosureGroup("Saved source links (\(links.count))") {
                                ForEach(links) { link in
                                    Text("\(link.kind.rawValue) · \(link.daytimePrecisionLabel) · \(link.daytimeTimestamp(link.start)) · \(link.sourceCalendarDay ?? "") \(link.timeZoneIdentifier ?? "")")
                                    Text("Saved source \(link.sourceID); evidence \(link.evidenceKey)").font(.caption)
                                }
                            }
                        }
                        Text("Recorded \(value.recordedAt.formatted()). \(value.timeZoneIdentifier)").font(.caption).foregroundStyle(.secondary)
                        Button("Correct response") { editing = value }
                            .accessibilityIdentifier("daytime-correct-\(value.id.uuidString)")
                        DisclosureGroup("Revision history") {
                            ForEach(ledger.revisions.filter { $0.id == value.id }, id: \.revisionID) { revision in
                                Text("\(revision.recordedAt.formatted()): \(revision.response.map(String.init) ?? revision.status.rawValue). \(revision.correctionReason ?? "Original observation")")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Daytime check-in")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .disabled(ledger == nil).accessibilityLabel("Record daytime check-in").accessibilityIdentifier("daytime-add-top")
            }
        }
        .sheet(isPresented: $adding, onDismiss: reload) { DaytimeCheckInEditor(original: nil) }
        .sheet(item: $editing, onDismiss: reload) { DaytimeCheckInEditor(original: $0) }
        .onAppear(perform: reload)
    }
    private func reload() {
        do { ledger = try repository.daytimeCheckIns(); failure = nil }
        catch { ledger = nil; failure = DaytimeDiaryError.unreadable.localizedDescription }
    }
}

struct DaytimeCheckInEditor: View {
    var original: DaytimeCheckIn? = nil
    var promptID: UUID? = nil
    var samplingProtocolID: UUID? = nil
    var samplingProtocolLabel: String? = nil
    var onSaved: ((DaytimeCheckIn) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = SessionRepository.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showDetails = false
    @State private var score: Int?
    @State private var status: DaytimeCheckIn.Status = .incomplete
    @State private var retrospective = false
    @State private var symptomTriggered = false
    @State private var assessedAt = Date()
    @State private var activity: DaytimeCheckIn.Activity?
    @State private var setting: DaytimeCheckIn.Setting = .unanswered
    @State private var coping: DaytimeCheckIn.Coping = .unanswered
    @State private var actions: Set<DaytimeCheckIn.Action> = []
    @State private var note = ""
    @State private var reason = ""
    @State private var reviewEnabled = false
    @State private var reviewFrom = Date()
    @State private var reviewTo = Date()
    @State private var reviewStatus: DaytimeEventReview.Status = .notReviewed
    @State private var eventIDs: Set<UUID> = []
    @State private var sourceLinks: [DaytimeSourceLink] = []
    @State private var events: [DaytimeEvent] = []
    @State private var eventsLoaded = false
    @State private var pending: DaytimeCheckIn?
    @State private var showSaveFailure = false
    @State private var failure: String?
    private var ratingQuestion: String {
        original != nil ? "How sleepy did you feel then?" :
            (retrospective ? "How sleepy did you feel?" : "How sleepy do you feel now?")
    }
    private var correctionContext: String? {
        guard let original else { return nil }
        guard let zone = TimeZone(secondsFromGMT: original.utcOffsetSeconds) else {
            return "Original observation time unavailable"
        }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
        return "Original observation: \(original.assessedAt.formatted(style))\nTime zone: \(original.timeZoneIdentifier)"
    }
    private var saveLabel: String {
        if original != nil { return pending == nil ? "Save correction" : "Retry exact correction" }
        return pending == nil ? "Save observation" : "Retry exact observation"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let correctionContext {
                        Text(correctionContext).font(.subheadline)
                            .accessibilityIdentifier("daytime-correction-context")
                    } else if retrospective { Text("Remembered observation: \(assessedAt.formatted())").font(.caption) }
                    Text("0 · Not sleepy     10 · Extremely sleepy").font(.subheadline)
                    Text(score.map { "Your rating: \($0)/10" } ?? "Choose a rating")
                        .font(.headline).accessibilityIdentifier("daytime-rating-summary")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 76 : 48))], spacing: 10) {
                        ForEach(0...10, id: \.self) { value in
                            Button {
                                score = value; status = .answered
                                if !retrospective && original == nil { assessedAt = Date() }
                            } label: {
                                Text(String(value)).font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(score == value ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(score == value ? Color.white : Color.primary)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Sleepiness \(value) of 10")
                                .accessibilityAddTraits(score == value ? .isSelected : [])
                                .accessibilityIdentifier("daytime-rating-\(value)")
                        }
                    }
                    if score != nil { Button("Clear rating") { score = nil; status = .incomplete } }
                    Text(original == nil ? "Choose a rating and tap Save. Details are optional." :
                            "Update this response and add a reason before saving.").font(.caption)
                    if original != nil { Text("The observation time and entry type stay unchanged.").font(.caption) }
                    if score == nil {
                        Picker("No rating", selection: $status) {
                            Text("Incomplete").tag(DaytimeCheckIn.Status.incomplete)
                            Text("Unsure").tag(DaytimeCheckIn.Status.unsure)
                            Text("Skipped").tag(DaytimeCheckIn.Status.skipped)
                        }
                    }
                } header: {
                    Text(ratingQuestion).accessibilityIdentifier("daytime-rating-question")
                }.disabled(pending != nil)
                if original == nil {
                    Section {
                        DisclosureGroup("Add details (optional)", isExpanded: $showDetails) {
                            Text("Activity, notes, earlier observations and event links.").font(.caption)
                        }.accessibilityIdentifier("daytime-details")
                    }
                }
                if original == nil && showDetails {
                    Section("Observation timing") {
                        if promptID == nil {
                            Toggle("Remembering an earlier observation", isOn: $retrospective)
                                .onChange(of: retrospective) { _ in score = nil; status = .incomplete; assessedAt = Date() }
                            if !retrospective { Toggle("Recording because I feel sleepy", isOn: $symptomTriggered) }
                            if retrospective {
                                DatePicker("Observed at", selection: $assessedAt, in: ...Date())
                                Text("This will be labeled retrospective, not a current assessment.").font(.caption)
                            }
                        }
                        Text("This is a custom 0–10 diary, not KSS or ESS.").font(.caption)
                    }.disabled(pending != nil)
                    Section("Optional context") {
                        Picker("Activity during observation", selection: $activity) {
                            Text("Not answered").tag(DaytimeCheckIn.Activity?.none)
                            ForEach(DaytimeCheckIn.Activity.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        Picker("Setting", selection: $setting) {
                            ForEach(DaytimeCheckIn.Setting.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Trying specifically to stay awake?", selection: $coping) {
                            ForEach(DaytimeCheckIn.Coping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.onChange(of: coping) { if $0 != .yes { actions.removeAll() } }
                        if coping == .yes {
                            ForEach(DaytimeCheckIn.Action.allCases, id: \.self) { action in
                                Toggle(action.rawValue, isOn: Binding(get: { actions.contains(action) }, set: {
                                    if $0 { actions.insert(action) } else { actions.remove(action) }
                                }))
                            }
                        }
                        TextField("Optional note (no names)", text: $note, axis: .vertical)
                        Text("Record actions already taken; this diary does not recommend caffeine or medication.").font(.caption)
                    }.disabled(pending != nil)
                } else if original != nil {
                    Section("Correction reason (required)") {
                        TextField("Why are you correcting this response?", text: $reason)
                            .accessibilityIdentifier("daytime-correction-reason")
                    }.disabled(pending != nil)
                }
                if original == nil && showDetails {
                    Section("Optional existing source links") {
                        NavigationLink("Review nap, medication or main-wake links (\(sourceLinks.count))") {
                            DaytimeSourcePicker(repository: repository, selected: $sourceLinks)
                        }.accessibilityIdentifier("daytime-source-open")
                    }.disabled(pending != nil)
                    Section("Optional event review") {
                        Toggle("Review an interval", isOn: $reviewEnabled)
                        if reviewEnabled {
                            DatePicker("Review from", selection: $reviewFrom, in: ...Date())
                            DatePicker("Review through", selection: $reviewTo, in: ...Date())
                            Picker("Unplanned sleep / interrupted activities", selection: $reviewStatus) {
                                ForEach(DaytimeEventReview.Status.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.onChange(of: reviewStatus) { if $0 != .eventsReported { eventIDs.removeAll() } }
                            if reviewStatus == .eventsReported {
                                Text("Select existing daytime events in this interval. Add a missing event from Daytime events first; linking never creates a second event.").font(.caption)
                                ForEach(events.filter { $0.occurredAt >= reviewFrom && $0.occurredAt <= reviewTo }) { event in
                                    Toggle("\(event.kind.rawValue), \(event.occurredAt.formatted())", isOn: Binding(get: { eventIDs.contains(event.id) }, set: {
                                        if $0 { eventIDs.insert(event.id) } else { eventIDs.remove(event.id) }
                                    }))
                                }
                            }
                        }
                    }.disabled(pending != nil || !eventsLoaded)
                }
                if let failure {
                    Section {
                        Text(failure).foregroundStyle(.red)
                        if !eventsLoaded { Button("Retry loading context", action: loadEvents) }
                        if pending != nil { Button("Edit entry before retry") { pending = nil; self.failure = nil } }
                    }
                }
                Button(saveLabel, action: save)
                    .accessibilityIdentifier("daytime-save")
            }
            .navigationTitle(original == nil ? "Daytime check-in" : "Correct observation")
            .alert(original == nil ? "Observation not saved" : "Correction not saved", isPresented: $showSaveFailure) {
                Button("Retry save", action: save)
                Button("Keep entry", role: .cancel) {}
            } message: { Text(failure ?? DaytimeDiaryError.notCommitted.localizedDescription) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending == nil ? "Save" : "Retry", action: save).accessibilityIdentifier("daytime-save-top")
                }
            }
            .onAppear {
                if let original { score = original.response; status = original.status; assessedAt = original.assessedAt }
                loadEvents()
            }
        }
    }
    private func loadEvents() {
        do { events = try repository.daytimeEvents().current; eventsLoaded = true; failure = nil }
        catch { failure = DaytimeDiaryError.unreadable.localizedDescription; eventsLoaded = false }
    }
    private func save() {
        do {
            guard eventsLoaded else { throw DaytimeDiaryError.unreadable }
            if pending == nil {
                let now = Date()
                if let original {
                    pending = try original.corrected(response: score, status: status, reason: reason, recordedAt: now)
                } else {
                    pending = try DaytimeCheckIn(assessedAt: score == nil && !retrospective ? now : assessedAt,
                        recordedAt: now, timeZoneIdentifier: TimeZone.current.identifier, response: score, status: status,
                        origin: retrospective ? .retrospective : (promptID == nil ? (symptomTriggered ? .symptomTriggered : .userInitiated) : .scheduled), activity: activity, setting: setting,
                        coping: coping, copingActions: actions, note: note, promptID: promptID,
                        eventReview: reviewEnabled ? DaytimeEventReview(from: reviewFrom, to: reviewTo, status: reviewStatus, eventIDs: Array(eventIDs)) : nil,
                        samplingProtocolID: samplingProtocolID, samplingProtocolLabel: samplingProtocolLabel, sourceLinks: sourceLinks.isEmpty ? nil : sourceLinks)
                }
            }
            guard let pending else { return }
            try repository.saveDaytimeCheckIn(pending)
            onSaved?(pending)
            dismiss()
        } catch { failure = (error as? DaytimeSourceSelectionError)?.localizedDescription ?? (error as? DaytimeDiaryError)?.localizedDescription ?? DaytimeDiaryError.notCommitted.localizedDescription; showSaveFailure = true }
    }
}
