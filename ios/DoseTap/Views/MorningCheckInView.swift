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
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    MorningCheckInQuickModeSection(viewModel: viewModel)
                    MorningSleepingSetupSection(viewModel: viewModel)
                    if !viewModel.isHistory {
                        if viewModel.hasCommittedDoseReconciliation {
                            Text("Medication choices will not be reapplied. Retrying saves only your morning answers. Use History for further medication corrections.")
                                .font(.footnote)
                                .accessibilityIdentifier("morning-medication-review-saved")
                        } else { MorningCheckInDoseReconciliationSection(viewModel: viewModel) }
                    }
                    else { Text("Treatment night: \(viewModel.sessionDate). These answers do not add doses or close tonight's session. Use Add / Correct Records for medication changes.").font(.footnote) }
                    MorningCheckInNightContextSection(viewModel: viewModel)
                    MorningCheckInMorningFunctioningSection(viewModel: viewModel)
                    MorningCheckInWorkSafetySection(viewModel: viewModel)
                    MorningCheckInClinicalContextSection(viewModel: viewModel)
                    MorningCheckInSymptomTogglesSection(viewModel: viewModel)
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
                    if !viewModel.isHistory { MorningCheckInRememberSettingsSection(viewModel: viewModel) }
                    MorningCheckInSubmitSection(
                        viewModel: viewModel,
                        dismissAction: { dismiss() },
                        onComplete: onComplete
                    )
                }
                .padding()
                .frame(width: geometry.size.width)
            }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isHistory ? "Cancel" : "Skip") {
                        dismiss()
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
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
