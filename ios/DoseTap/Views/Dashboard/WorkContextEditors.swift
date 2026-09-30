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
    @State private var actualTimes = false
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
                        Toggle("I know the actual start and end", isOn: $actualTimes)
                        if actualTimes {
                            DatePicker("Actual start", selection: $actualStart)
                            DatePicker("Actual end", selection: $actualEnd)
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
            .navigationTitle("Work context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save revision", action: submit).disabled(mode == "Roster" && !datesReviewed) }
            }
        }
    }
    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    private func submit() {
        guard TimeZone(identifier: zone) != nil else { error = "Enter a valid timezone identifier."; return }
        var next = document; let now = Date(); next.revision = UUID()
        if mode == "Roster" {
            guard minutes.isEmpty || Int(minutes) != nil else { error = "Enter whole planned minutes or leave them blank."; return }
            next.rosters.append(WorkRoster(effectiveFrom: dateKey(from), effectiveTo: dateKey(through), timeZoneIdentifier: zone, weekdays: weekdays, plannedShiftMinutes: Int(minutes), recordedAt: now))
        } else {
            var occurrence = WorkOccurrence(workDate: dateKey(from), timeZoneIdentifier: zone, plannedWorking: planned == "Unchanged" ? nil : planned == "Scheduled", attendance: updateAttendance ? attendance : nil, reason: reason, recordedAt: now)
            if actualTimes { occurrence.actualStart = actualStart; occurrence.actualEnd = actualEnd }
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
