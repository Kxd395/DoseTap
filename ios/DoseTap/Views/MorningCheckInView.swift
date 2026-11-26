//
//  MorningCheckInView.swift
//  DoseTap
//
//  Morning questionnaire with progressive disclosure:
//  - Quick Mode: 5 core questions (30 seconds)
//  - Deep Dive: Conditional expansion for symptoms
//

import SwiftUI
import DoseCore

public struct MorningCheckInView: View {
    @StateObject private var viewModel: MorningCheckInViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPainEntryEditor = false
    @State private var usingSavedPainPattern = false
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?
    /// Set after the first change the user makes, so Cancel and swipe-down
    /// cannot silently discard answers (DOSETAP-92).
    @State private var hasUnsavedEdits = false
    @State private var editTrackingArmed = false
    @State private var showDiscardConfirmation = false

    private enum SectionLink: String, CaseIterable {
        case sleep = "Sleep quality"
        case night = "Night context"
        case symptoms = "Symptoms"
        case notes = "Notes"
    }

    let onComplete: () -> Void

    init(history: HistoryQuestionnaireSnapshot, existing: StoredMorningCheckIn?, referenceTime: Date,
         onReview: @escaping (SQLiteStoredMorningCheckIn) -> Void) {
        let plan = SessionRepository.shared.plannedSleepingSetup(sessionID: history.history.sessionId, sessionDate: history.history.sessionDate)
        let model = existing.map { MorningCheckInViewModel(sessionId: history.history.sessionId, sessionDate: history.history.sessionDate, existing: $0, plannedSetup: plan) }
            ?? MorningCheckInViewModel(sessionId: history.history.sessionId, sessionDate: history.history.sessionDate, loadRememberedSettings: false, plannedSetup: plan)
        model.historyReview = onReview
        if existing == nil { model.shiftStartAt = referenceTime; model.shiftEndAt = referenceTime; model.nextRequiredWakeAt = referenceTime }
        _viewModel = StateObject(wrappedValue: model)
        self.onComplete = {}
    }

    public init(sessionId: String, sessionDate: String, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate,
            plannedSetup: SessionRepository.shared.plannedSleepingSetup(sessionID: sessionId, sessionDate: sessionDate)))
        self.onComplete = onComplete
    }

    public init(sessionId: String, sessionDate: String, existingCheckIn: StoredMorningCheckIn, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate, existing: existingCheckIn,
            plannedSetup: SessionRepository.shared.plannedSleepingSetup(sessionID: sessionId, sessionDate: sessionDate)))
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                questionnaire
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Morning Check-In")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(SectionLink.allCases, id: \.self) { section in
                                Button(section.rawValue) { scroll.scrollTo(section, anchor: .top) }
                            }
                        } label: {
                            Label("Go to section", systemImage: "list.bullet")
                        }
                        .accessibilityIdentifier("morning-section-menu")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // "Cancel", not "Close check-in": closing never completes
                        // the check-in or the night, and the old name read as if it did.
                        Button("Cancel") {
                            if hasUnsavedEdits {
                                showDiscardConfirmation = true
                            } else {
                                dismiss()
                                onComplete()
                            }
                        }
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("morning-check-in-cancel")
                    }
                }
            }
            .confirmationDialog("Discard your check-in answers?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Answers", role: .destructive) {
                    dismiss()
                    onComplete()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your answers are not saved until you tap Complete Check-In.")
            }
            .onReceive(viewModel.objectWillChange) { _ in
                if editTrackingArmed && !viewModel.isSubmitting { hasUnsavedEdits = true }
            }
            .task {
                // Initial loading publishes changes too; only later changes are edits.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                editTrackingArmed = true
            }
            .sheet(isPresented: $showPainEntryEditor) {
                GranularPainEntryEditorView(initialEntry: editingPainEntry,
                                           replacesInitialEntry: !usingSavedPainPattern,
                                           isMorningPatternReview: usingSavedPainPattern,
                                           existingMorningEntries: viewModel.painEntries) { result in
                    viewModel.upsertPainEntries(result.entries, replacingEntryKey: result.replacedEntryKey)
                }
                // The sheet can be created before its bound entry arrives. Reset the
                // editor state when the entry or review mode changes.
                .id("\(editingPainEntry?.entryKey ?? "new")-\(usingSavedPainPattern)")
            }
        }
        // Applied to the outer navigation container so the sheet honors it.
        .interactiveDismissDisabled(hasUnsavedEdits)
    }

    private var questionnaire: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    MorningCheckInQuickModeSection(viewModel: viewModel)
                        .id(SectionLink.sleep)
                    MorningSleepingSetupSection(viewModel: viewModel)
                    if !viewModel.isHistory {
                        MorningDoseHistoryReviewSection(viewModel: viewModel)
                    }
                    else { Text("Treatment night: \(viewModel.sessionDate). These answers do not add doses or close tonight's session. Use Add / Correct Records for medication changes.").font(.footnote) }
                    MorningCheckInNightContextSection(viewModel: viewModel)
                        .id(SectionLink.night)
                    MorningCheckInMorningFunctioningSection(viewModel: viewModel)
                    MorningCheckInWorkSafetySection(viewModel: viewModel)
                    MorningCheckInClinicalContextSection(viewModel: viewModel)
                    MorningCheckInSymptomTogglesSection(viewModel: viewModel)
                        .id(SectionLink.symptoms)
                    if viewModel.hasPhysicalSymptoms {
                        MorningCheckInPhysicalSymptomsSection(
                            viewModel: viewModel,
                            showPainEntryEditor: $showPainEntryEditor,
                            editingPainEntry: $editingPainEntry,
                            usingSavedPainPattern: $usingSavedPainPattern
                        )
                    }
                    if viewModel.hasRespiratorySymptoms {
                        MorningCheckInRespiratorySymptomsSection(viewModel: viewModel)
                    }
                    MorningCheckInSleepEnvironmentSection(viewModel: viewModel)
                    MorningCheckInSleepTherapySection(viewModel: viewModel)
                    MorningCheckInNarcolepsySection(viewModel: viewModel)
                    MorningCheckInNotesSection(viewModel: viewModel)
                        .id(SectionLink.notes)
                    if !viewModel.isHistory { MorningCheckInRememberSettingsSection(viewModel: viewModel) }
                }
                .padding()
                .frame(width: geometry.size.width)
            }
            .accessibilityIdentifier("morning-check-in-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MorningCheckInSubmitSection(
                    viewModel: viewModel,
                    dismissAction: { dismiss() },
                    onComplete: onComplete,
                    statusMaximumHeight: geometry.size.height / 4
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
            Text(viewModel.isHistory ? "Review a Past Morning" : "Good Morning!")
                .font(.title2.bold())
            Text(viewModel.isHistory ? "Answer for treatment night \(viewModel.sessionDate)" : "Quick check-in about last night's sleep")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }
}

#Preview { MorningCheckInView(sessionId: "preview-session", sessionDate: "2025-01-01") }
