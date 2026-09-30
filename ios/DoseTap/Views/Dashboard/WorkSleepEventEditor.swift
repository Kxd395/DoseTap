import SwiftUI
import DoseCore

/// The reviewer supplies the actual main-sleep interval and exact adjacent shift identities.
struct WorkSleepEventEditor: View {
    let sleepID: String, sleepDate: String
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zone = TimeZone.current.identifier
    @State private var previousDate = ""
    @State private var followingDate = ""
    @State private var startKnown = false
    @State private var endKnown = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var preceding = WorkWakingStatus.unknown
    @State private var following = WorkWakingStatus.unknown
    @State private var precedingID: UUID?
    @State private var followingID: UUID?
    @State private var snapshotID: UUID?
    @State private var postBlockID: UUID?
    @State private var postBlockIndex = ""
    @State private var reviewed = false
    @State private var error: String?
    private var shifts: [WorkShiftEvent] { document.latestShiftEvents(asOf: Date()) }
    private var snapshots: [WorkPlanSnapshot] {
        (document.planSnapshots ?? []).filter { $0.sessionID.map { "session:" + $0 == sleepID } == true }
    }
    private func shiftLabel(_ event: WorkShiftEvent) -> String {
        (event.workDate ?? "Work date unknown") + " • " + event.positionLabel + " • " + event.status.rawValue
            + " • " + String(event.shiftID.uuidString.prefix(6))
    }
    private func shiftPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("No selected shift / unknown").tag(Optional<UUID>.none)
            ForEach(shifts) { Text(shiftLabel($0)).tag(Optional($0.shiftID)) }
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reviewed main sleep " + sleepDate) {
                    TextField("Timezone identifier", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Preceding waking date (YYYY-MM-DD)", text: $previousDate).accessibilityIdentifier("work-sleep-prior-date")
                    TextField("Following waking date (YYYY-MM-DD)", text: $followingDate).accessibilityIdentifier("work-sleep-next-date")
                    Toggle("Main-sleep start is known", isOn: $startKnown)
                    if startKnown { DatePicker("Reviewed sleep start", selection: $start) }
                    Toggle("Main-sleep end is known", isOn: $endKnown)
                    if endKnown { DatePicker("Reviewed sleep end", selection: $end) }
                    Text("Enter reviewed sleep boundaries. Session-end and check-in completion times are not substituted. Unknown boundaries remain unclassified.").font(.caption)
                }
                Section("Adjacent waking periods") {
                    Picker("Preceding period", selection: $preceding) { ForEach([WorkWakingStatus.unknown, .work, .off], id: \.self) { Text($0.rawValue).tag($0) } }
                    shiftPicker("Preceding shift", selection: $precedingID)
                    Picker("Following period", selection: $following) { ForEach([WorkWakingStatus.unknown, .work, .off], id: \.self) { Text($0.rawValue).tag($0) } }
                    shiftPicker("Following shift", selection: $followingID)
                    Text("Worked periods require an exact saved shift link. Plans do not establish attendance. Overnight work can use explicit main-sleep links without a calendar-date guess.").font(.caption)
                    if preceding == .off && following == .off {
                        shiftPicker("Previous block's final shift (optional)", selection: $postBlockID)
                        TextField("Reviewed main-sleep number after that block (2 or later)", text: $postBlockIndex).keyboardType(.numberPad)
                    }
                }
                Section("Planning evidence") {
                    Picker("Plan source", selection: $snapshotID) {
                        Text("Review-time plan; historical timing unknown").tag(Optional<UUID>.none)
                        ForEach(snapshots) { snapshot in
                            Text("Pre-sleep capture " + snapshot.capturedAt.formatted()).tag(Optional(snapshot.id))
                        }
                    }
                    Text("Only an existing immutable capture belonging to this exact session is offered. Saving this review cannot create a historical pre-sleep plan.").font(.caption)
                    Toggle("I reviewed this main sleep and adjacent waking periods", isOn: $reviewed).accessibilityIdentifier("work-sleep-events-reviewed")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("work-sleep-events-error") }
            }.environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                .navigationTitle("Main-sleep shift links")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save shift links", action: submit).disabled(!reviewed) }
                }.onAppear(perform: load)
        }
    }
    private func load() {
        guard let saved = document.association(for: sleepID, asOf: Date()) else { return }
        zone = saved.timeZoneIdentifier; previousDate = saved.precedingDate; followingDate = saved.followingDate
        snapshotID = saved.planSnapshotID
        guard let context = saved.eventContext else { return }
        startKnown = context.mainSleepStart != nil; endKnown = context.mainSleepEnd != nil
        if let value = context.mainSleepStart { start = value }; if let value = context.mainSleepEnd { end = value }
        preceding = context.precedingStatus; following = context.followingStatus
        precedingID = context.precedingShiftID; followingID = context.followingShiftID
        postBlockID = context.postBlockReferenceShiftID; postBlockIndex = context.postBlockMainSleepIndex.map(String.init) ?? ""
    }
    private func submit() {
        let now = Date()
        guard TimeZone(identifier: zone) != nil, WorkContextDocument.day(previousDate, zone: zone) != nil,
              WorkContextDocument.day(followingDate, zone: zone) != nil else { error = "Review the timezone and both waking dates."; return }
        guard postBlockIndex.isEmpty || Int(postBlockIndex).map({ (2...366).contains($0) }) == true else { error = "Use a whole post-block sleep number from 2 through 366, or leave it unknown."; return }
        let snapshot = snapshotID.flatMap { id in snapshots.first { $0.id == id } }
        guard snapshotID == nil || (snapshot != nil && startKnown && snapshot!.capturedAt <= start) else { error = "The selected plan must belong to this session and precede the reviewed sleep start."; return }
        var context = WorkSleepEventContext(mainSleepStart: startKnown ? start : nil, mainSleepEnd: endKnown ? end : nil,
            precedingStatus: preceding, followingStatus: following, precedingShiftID: precedingID,
            followingShiftID: followingID, wakingPeriodsReviewed: reviewed)
        if preceding == .off && following == .off { context.postBlockReferenceShiftID = postBlockID; context.postBlockMainSleepIndex = Int(postBlockIndex) }
        var association = WorkSleepAssociation(sleepID: sleepID, precedingDate: previousDate, followingDate: followingDate,
            timeZoneIdentifier: zone, plannedAt: snapshot?.capturedAt ?? now, recordedAt: now)
        association.planSnapshotID = snapshotID; association.eventContext = context
        var next = document; next.schemaVersion = 3; next.revision = UUID(); next.associations.append(association)
        guard next.isValid else { error = "Review the sleep boundaries and shift links; end must follow start and actual evidence cannot be future-dated."; return }
        do { try save(next); dismiss() } catch { self.error = error.localizedDescription }
    }
}
