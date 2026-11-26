import SwiftUI
import DoseCore

struct WorkContextEditor: View {
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "Roster"
    @State private var from = Date()
    @State private var through = Date()
    @State private var zone = TimeZone.current.identifier
    @State private var weekdays: Set<Int> = []
    @State private var minutes = ""
    @State private var datesReviewed = false
    @State private var attendance = WorkAttendance.unknown
    @State private var updateAttendance = false
    @State private var planned = "Unchanged"
    @State private var reason = ""
    @State private var scheduledMode = "Unchanged"
    @State private var scheduledStart = Date()
    @State private var scheduledEnd = Date()
    @State private var breakMode = "Unchanged"
    @State private var plannedBreak = Date()
    @State private var actualMode = "Unchanged"
    @State private var actualStartKnown = false
    @State private var actualEndKnown = false
    @State private var actualStart = Date()
    @State private var actualEnd = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Record", selection: $mode) { Text("Roster").tag("Roster"); Text("Work date").tag("Work date") }
                    .pickerStyle(.segmented)
                Section("Work timezone") {
                    TextField("Timezone identifier", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("This context does not change your wake schedule, medication or alarms.").font(.caption)
                }
                if mode == "Roster" {
                    Section("Effective roster dates") {
                        DatePicker("First covered work date", selection: $from, displayedComponents: .date)
                        DatePicker("Last covered work date", selection: $through, displayedComponents: .date)
                        ForEach(1...7, id: \.self) { day in
                            Toggle(Calendar(identifier: .gregorian).weekdaySymbols[day - 1], isOn: Binding(
                                get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                        }
                        TextField("Planned shift minutes (optional)", text: $minutes).keyboardType(.numberPad)
                        Toggle("I reviewed these dates and planned workdays", isOn: $datesReviewed)
                        Text("An empty weekday list explicitly means no planned work in this date range. No attendance or actual hours are inferred.").font(.caption)
                    }
                } else {
                    Section("One work date") {
                        DatePicker("Work date", selection: $from, displayedComponents: .date)
                        Picker("Planned work", selection: $planned) {
                            ForEach(["Unchanged", "Scheduled", "Not scheduled"], id: \.self) { Text($0) }
                        }
                        Toggle("Update confirmed attendance", isOn: $updateAttendance)
                        Picker("Confirmed attendance", selection: $attendance) {
                            Text("Unanswered / uncertain").tag(WorkAttendance.unknown)
                            Text("Worked").tag(WorkAttendance.worked)
                            Text("Did not work").tag(WorkAttendance.notWorked)
                        }.disabled(!updateAttendance)
                        TextField("Change reason (extra shift, leave, swap…)", text: $reason, axis: .vertical)
                        Picker("Scheduled times", selection: $scheduledMode) {
                            ForEach(["Unchanged", "Enter times", "Clear times"], id: \.self) { Text($0) }
                        }
                        if scheduledMode == "Enter times" {
                            DatePicker("Scheduled start", selection: $scheduledStart)
                            DatePicker("Scheduled end", selection: $scheduledEnd)
                        }
                        Picker("Planned break", selection: $breakMode) {
                            ForEach(["Unchanged", "Enter time", "Clear time"], id: \.self) { Text($0) }
                        }
                        if breakMode == "Enter time" { DatePicker("Planned break time", selection: $plannedBreak) }
                        Picker("Actual times", selection: $actualMode) {
                            ForEach(["Unchanged", "Enter times", "Clear times"], id: \.self) { Text($0) }
                        }
                        if actualMode == "Enter times" {
                            Toggle("Actual start is known", isOn: $actualStartKnown)
                            if actualStartKnown { DatePicker("Actual start", selection: $actualStart) }
                            Toggle("Actual end is known", isOn: $actualEndKnown)
                            if actualEndKnown { DatePicker("Actual end", selection: $actualEnd) }
                        }
                        Text("Scheduled is a plan. Only an explicit attendance answer establishes Worked or Did not work.").font(.caption)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("work-context-save-error") }
                Section("Recorded history") {
                    Text("\(document.rosters.count) roster revisions • \(document.occurrences.count) work-date revisions")
                    ForEach(document.rosters.reversed()) { roster in
                        Text("\(roster.effectiveFrom)–\(roster.effectiveTo) • \(roster.timeZoneIdentifier)").font(.caption)
                    }
                }
            }
            .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
            .onChange(of: from) { _ in resetAnchorEdits() }
            .onChange(of: zone) { _ in resetAnchorEdits() }
            .onChange(of: actualMode) { value in
                if value == "Enter times" {
                    let saved = document.resolvedWorkDate(dateKey(from), timeZoneIdentifier: zone, asOf: Date())
                    actualStartKnown = saved?.actualStart != nil; actualEndKnown = saved?.actualEnd != nil
                    if let value = saved?.actualStart { actualStart = value }
                    if let value = saved?.actualEnd { actualEnd = value }
                }
            }
            .navigationTitle("Work context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save revision", action: submit).disabled(mode == "Roster" && !datesReviewed) }
            }
        }
    }
    private func resetAnchorEdits() { actualMode = "Unchanged"; scheduledMode = "Unchanged"; breakMode = "Unchanged" }
    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    private func submit() {
        guard TimeZone(identifier: zone) != nil else { error = "Enter a valid timezone identifier."; return }
        if mode == "Work date", scheduledMode == "Enter times", scheduledEnd <= scheduledStart { error = "Scheduled end must be after scheduled start."; return }
        if mode == "Work date", actualMode == "Enter times" {
            guard actualStartKnown || actualEndKnown else { error = "Enter at least one known actual endpoint, or choose Clear times."; return }
            if actualStartKnown && actualEndKnown && actualEnd <= actualStart { error = "Actual end must be after actual start."; return }
            if (actualStartKnown && actualStart > Date()) || (actualEndKnown && actualEnd > Date()) { error = "Actual times cannot be in the future. Enter future work under Scheduled times."; return }
        }
        var next = document; let now = Date(); next.revision = UUID()
        if mode == "Roster" {
            guard minutes.isEmpty || Int(minutes) != nil else { error = "Enter whole planned minutes or leave them blank."; return }
            next.rosters.append(WorkRoster(effectiveFrom: dateKey(from), effectiveTo: dateKey(through), timeZoneIdentifier: zone, weekdays: weekdays, plannedShiftMinutes: Int(minutes), recordedAt: now))
        } else {
            var occurrence = WorkOccurrence(workDate: dateKey(from), timeZoneIdentifier: zone, plannedWorking: planned == "Unchanged" ? nil : planned == "Scheduled", attendance: updateAttendance ? attendance : nil, reason: reason, recordedAt: now)
            occurrence.scheduledTimesReviewed = scheduledMode == "Unchanged" ? nil : true
            occurrence.breakReviewed = breakMode == "Unchanged" ? nil : true
            occurrence.actualTimesReviewed = actualMode == "Unchanged" ? nil : true
            if scheduledMode == "Enter times" { occurrence.scheduledStart = scheduledStart; occurrence.scheduledEnd = scheduledEnd }
            if breakMode == "Enter time" { occurrence.plannedBreakAt = plannedBreak }
            if actualMode == "Enter times" { occurrence.actualStart = actualStartKnown ? actualStart : nil; occurrence.actualEnd = actualEndKnown ? actualEnd : nil }
            next.occurrences.append(occurrence)
        }
        do { try save(next); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct WorkSleepContextEditor: View {
    let sleepID: String
    let sleepDate: String
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var eventEditor = false
    @State private var previous = ""
    @State private var following = ""
    @State private var zone = TimeZone.current.identifier
    @State private var reviewed = false
    @State private var overrideEnabled = false
    @State private var phase = WorkPhase.unknown
    @State private var reason = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Button("Review sleep-to-shift links (including overnight work)") { eventEditor = true }.accessibilityIdentifier("work-sleep-events-open")
                Section("Main sleep \(sleepDate)") {
                    TextField("Preceding waking date (YYYY-MM-DD)", text: $previous)
                    TextField("Following waking date (YYYY-MM-DD)", text: $following)
                    TextField("Timezone identifier", text: $zone).textInputAutocapitalization(.never)
                    Toggle("I reviewed this main sleep and its adjacent waking dates (daytime shifts)", isOn: $reviewed)
                    Text("For an after-midnight start, retain the intended waking-period dates. Naps and ambiguous overnight-shift associations remain unclassified. This saves a reviewed plan snapshot now; it does not claim the plan was recorded before a historical sleep.").font(.caption)
                }
                Section("Optional explicit override") {
                    Toggle("Override derived phase", isOn: $overrideEnabled)
                    if overrideEnabled {
                        Picker("Reviewed phase", selection: $phase) { ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag($0) } }
                        TextField("Required reason", text: $reason, axis: .vertical)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Review sleep context")
                .sheet(isPresented: $eventEditor) {
                    WorkSleepEventEditor(sleepID: sleepID, sleepDate: sleepDate, document: document) { try save($0); dismiss() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save review", action: submit).disabled(!reviewed) }
                }
                .onAppear {
                    if let saved = document.association(for: sleepID, asOf: Date()) {
                        previous = saved.precedingDate; following = saved.followingDate; zone = saved.timeZoneIdentifier
                    }
                }
        }
    }
    private func submit() {
        let now = Date()
        var association = WorkSleepAssociation(sleepID: sleepID, precedingDate: previous, followingDate: following, timeZoneIdentifier: zone, plannedAt: now, recordedAt: now)
        association.daytimeAssociationReviewed = reviewed
        if overrideEnabled { association.overridePhase = phase; association.overrideReason = reason }
        var next = document; next.revision = UUID(); next.associations.append(association)
        do { try save(next); dismiss() } catch { self.error = error.localizedDescription }
    }
}
