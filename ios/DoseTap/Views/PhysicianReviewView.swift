import SwiftUI
import DoseCore
import os

private let physicianReviewLogger = Logger(subsystem: "com.dosetap.app", category: "PhysicianReview")

struct PhysicianPreparedSources: Sendable {
    let period: PhysicianReportPeriod
    let observations: [PhysicianReportObservation]
    let contexts: [PhysicianReportContext]
    let capturedAt: Date
    let coverageDescription: String
    let includePartialMetrics: Bool
}

struct PhysicianReviewView: View {
    let prepareSources: (PhysicianReportPeriod) async throws -> PhysicianPreparedSources
    let selectionIdentity: String
    let selectionDescription: String
    @ObservedObject var repository: SessionRepository
    @State private var prepared: PhysicianPreparedSources?
    @State private var preparation: Task<Void, Never>?
    @State private var preparing = false
    @State private var preparationID = UUID()
    @State private var exampleLimit = 100
    @State private var draftNotes: [VisitPreparationNote] = []
    @State private var ledger = PhysicianVisitLedger()
    @State private var reports: [PhysicianReportSnapshot] = []
    @State private var range = "6 Months"
    @State private var customStart = Date().addingTimeInterval(-28 * 86400)
    @State private var customEnd = Date()
    @State private var visitDate = Date()
    @State private var visitNote = ""
    @State private var editingVisit: PhysicianVisit?
    @State private var sourceObservations: [PhysicianReportObservation] = []
    @State private var selectedExamples: Set<String> = []
    @State private var activity = ""
    @State private var opportunity = VisitPreparationNote.Opportunity.observed
    @State private var comment = ""
    @State private var questions = ""
    @State private var preview: PhysicianReportSnapshot?
    @State private var failure: String?
    @State private var ready = false
    @FocusState private var textFocused: Bool
    private let choices = ["7 Days", "28 Days", "90 Days", "6 Months", "12 Months", "Since completed visit", "Custom"]

    var body: some View {
        Form {
            Section("Report period") {
                Picker("Period", selection: $range) { ForEach(choices, id: \.self) { Text($0) } }
                    .pickerStyle(.menu).accessibilityIdentifier("physician-report-period")
                if range == "Custom" {
                    DatePicker("Start inclusive", selection: $customStart)
                    DatePicker("End exclusive", selection: $customEnd, in: ...Date())
                }
                Text("Calendar timezone: \(TimeZone.current.identifier). The current day ends at capture time.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(selectionDescription).font(.caption)
                Button(preparing ? "Preparing sources…" : "Prepare selected period", action: preparePeriod)
                    .disabled(!ready || preparing).accessibilityIdentifier("physician-prepare-period")
                if let prepared {
                    Text("Sources captured \(prepared.capturedAt.formatted()). Saving a preview retains these sources. Prepare again to refresh.").font(.caption)
                    Text(prepared.coverageDescription).font(.caption)
                }
            }
            Section("Completed visits") {
                Text("Record visits that actually occurred. Future or cancelled appointments do not reset the report period.").font(.caption)
                ForEach(ledger.current) { visit in
                    Button {
                        editingVisit = visit; visitDate = visit.occurredAt; visitNote = visit.note
                    } label: {
                        VStack(alignment: .leading) {
                            Text(visit.occurredAt, style: .date)
                            if !visit.note.isEmpty { Text(visit.note).font(.caption) }
                            Text("Edit completed visit").font(.caption)
                        }
                    }
                }
                DatePicker("Completed at", selection: $visitDate, in: ...Date())
                TextField("Visit note (optional)", text: $visitNote)
                Button(editingVisit == nil ? "Save completed visit" : "Save visit correction", action: saveVisit)
                    .disabled(!ready).accessibilityIdentifier("physician-save-visit")
                if editingVisit != nil { Button("Cancel correction") { editingVisit = nil; visitNote = "" } }
            }
            Section("Prepare for sleep visit") {
                Text("Unscored notes about usual activities and uncertainty. These notes do not predict or fill in an ESS or another clinical scale.").font(.caption)
                TextField("Activity or context", text: $activity).accessibilityIdentifier("physician-note-activity").focused($textFocused)
                Picker("Opportunity", selection: $opportunity) {
                    Text("Opportunity with observation").tag(VisitPreparationNote.Opportunity.observed)
                    Text("No recent opportunity").tag(VisitPreparationNote.Opportunity.noRecentOpportunity)
                    Text("Avoided or stopped activity").tag(VisitPreparationNote.Opportunity.avoidedOrStopped)
                    Text("Uncertain recollection").tag(VisitPreparationNote.Opportunity.uncertainRecollection)
                    Text("No information collected").tag(VisitPreparationNote.Opportunity.notCollected)
                }
                TextField("What happened or remains uncertain", text: $comment, axis: .vertical).accessibilityIdentifier("physician-note-comment").focused($textFocused)
                DisclosureGroup("Select recorded examples for this note") {
                    ForEach(sourceObservations.prefix(exampleLimit)) { value in
                        Button {
                            if selectedExamples.contains(value.id) { selectedExamples.remove(value.id) }
                            else { selectedExamples.insert(value.id) }
                        } label: {
                            Label(value.metricID + " • " + (value.observedAt?.formatted() ?? "Unknown time"),
                                  systemImage: selectedExamples.contains(value.id) ? "checkmark.circle.fill" : "circle")
                        }.accessibilityValue(selectedExamples.contains(value.id) ? "Selected" : "Not selected")
                    }
                    if exampleLimit < sourceObservations.count {
                        Button("Show more recorded examples") { exampleLimit += 100 }
                    }
                }
                Button("Include reviewed activity note", action: addNote)
                    .disabled(prepared == nil || activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("physician-add-note")
                if !activity.isEmpty || !comment.isEmpty { Button("Clear current note draft") { clearNote() } }
                ForEach(draftNotes) { note in
                    VStack(alignment: .leading) {
                        Text(note.activity).font(.headline)
                        Text(note.opportunity.label)
                        Text(note.comment)
                        Button("Remove this note") { draftNotes.removeAll { $0.id == note.id } }
                    }
                }
                TextField("Visit questions (one per line)", text: $questions, axis: .vertical).accessibilityIdentifier("physician-questions").focused($textFocused)
            }
            Section {
                Button("Save and preview report", action: makePreview).disabled(!ready || prepared == nil || preparing)
                    .accessibilityIdentifier("physician-create-preview")
                Text("A preview stays unchanged after later corrections. Sharing is a separate action from the preview.").font(.caption)
            }
            Section("Saved previews") {
                if reports.isEmpty { Text("No saved previews") }
                ForEach(reports) { report in
                    Button { preview = report } label: {
                        VStack(alignment: .leading) {
                            Text(report.period.label)
                            Text(report.generatedAt, style: .date).font(.caption)
                            Text("\(report.observations.count) source observations").font(.caption)
                        }
                    }.accessibilityIdentifier("physician-saved-preview-" + report.id.uuidString)
                }
            }
        }.navigationTitle("Physician review")
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { textFocused = false }.accessibilityIdentifier("physician-keyboard-done") } }
            .task { reload() }
            .onDisappear { preparation?.cancel() }
            .onChange(of: range) { _ in invalidatePrepared() }
            .onChange(of: customStart) { _ in invalidatePrepared() }
            .onChange(of: customEnd) { _ in invalidatePrepared() }
            .onChange(of: selectionIdentity) { _ in invalidatePrepared() }
            .sheet(item: $preview) { PhysicianReportPreview(snapshot: $0) }
            .alert("Review could not be saved", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
    }
    private func reload() {
        do { ledger = try repository.physicianVisits(); reports = try repository.physicianReports(); ready = true }
        catch { ready = false; failure = "Saved records could not be read. Nothing has been overwritten. Try reopening this screen." }
    }
    private func saveVisit() {
        do {
            let now = Date()
            let visit = try PhysicianVisit(id: editingVisit?.id ?? UUID(), predecessorID: editingVisit?.revisionID,
                                           occurredAt: visitDate, recordedAt: now, note: visitNote, now: now)
            try repository.savePhysicianVisit(visit)
            editingVisit = nil; visitNote = ""; reload(); if range == "Since completed visit" { invalidatePrepared() }
        } catch { failure = "The completed visit was not saved. Check its date and note length, then retry. A concurrent correction requires reopening the visit." }
    }
    private func invalidatePrepared() {
        preparation?.cancel(); preparationID = UUID(); preparation = nil; preparing = false; prepared = nil; exampleLimit = 100
        sourceObservations = []; selectedExamples = []
    }
    private func preparePeriod() {
        invalidatePrepared(); preparing = true
        let ticket = preparationID
        preparation = Task { @MainActor in
            do {
                let selection: PhysicianReportRange
                switch range {
                case "7 Days": selection = .days7
                case "28 Days": selection = .days28
                case "90 Days": selection = .days90
                case "12 Months": selection = .twelveMonths
                case "Since completed visit": selection = .sinceCompletedVisit
                case "Custom": selection = .custom(start: customStart, endExclusive: customEnd)
                default: selection = .sixMonths
                }
                let period = try PhysicianReportPeriod.resolve(selection, ledger: repository.physicianVisits(), asOf: Date(), timeZone: .current)
                let sources = try await prepareSources(period)
                try Task.checkCancellation()
                guard ticket == preparationID, sources.period == period, sources.capturedAt >= period.capturedAt, sources.capturedAt <= Date() else { throw PhysicianReviewError.invalidPeriod }
                prepared = sources
                sourceObservations = sources.observations.filter { $0.observedAt.map(period.contains) ?? true }
                preparing = false
            } catch is CancellationError { if ticket == preparationID { preparing = false } }
            catch PhysicianReviewError.missingCompletedVisit {
                guard ticket == preparationID else { return }
                preparing = false; failure = "Save a completed visit first, or choose another report period."
            } catch {
                guard ticket == preparationID else { return }
                physicianReviewLogger.error("Physician report source preparation failed")
                preparing = false; failure = "Sources were not prepared. Check the dates and selected filters, then retry. Unreadable local records cannot be replaced with an empty report."
            }
        }
    }
    private func clearNote() { activity = ""; comment = ""; selectedExamples = []; opportunity = .observed }
    private func addNote() {
        let name = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 300, comment.count <= 4000 else {
            failure = "Provide an activity of 1–300 characters and a comment of up to 4,000 characters."; return
        }
        draftNotes.append(.init(activity: name, opportunity: opportunity, comment: comment, evidenceIDs: selectedExamples.sorted(),
            reviewedAt: Date(), selectedForSharing: true)); clearNote()
    }
    private func makePreview() {
        do {
            guard let prepared, prepared.period.timeZoneIdentifier == TimeZone.current.identifier else { throw PhysicianReviewError.invalidPeriod }
            guard activity.isEmpty && comment.isEmpty else {
                failure = "Include the current reviewed activity note, or clear its draft, before saving the preview."; return
            }
            let info = Bundle.main.infoDictionary ?? [:]
            let version = "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))"
            let report = try PhysicianReportSnapshot(period: prepared.period, observations: prepared.observations, notes: draftNotes,
                questions: questions.split(separator: "\n").map(String.init), appVersion: version, generatedAt: Date(),
                coverageDescription: prepared.coverageDescription, contexts: prepared.contexts, includePartialMetrics: prepared.includePartialMetrics)
            try repository.savePhysicianReport(report); reload(); preview = report
            physicianReviewLogger.info("Immutable physician report preview saved")
        } catch {
            physicianReviewLogger.error("Physician report preview could not be saved")
            failure = "The preview was not saved. Prepare the selected period again if the timezone changed. Keep linked examples within that period and remove or review notes with unavailable examples. Your draft remains available."
        }
    }
}
