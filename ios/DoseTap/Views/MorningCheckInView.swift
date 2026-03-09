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
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?

    let onComplete: () -> Void

    public init(sessionId: String, sessionDate: String, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate))
        self.onComplete = onComplete
    }

    public init(sessionId: String, sessionDate: String, existingCheckIn: StoredMorningCheckIn, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate, existing: existingCheckIn))
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    MorningCheckInQuickModeSection(viewModel: viewModel)
                    MorningCheckInDoseReconciliationSection(viewModel: viewModel)
                    MorningCheckInMorningFunctioningSection(viewModel: viewModel)
                    MorningCheckInSymptomTogglesSection(viewModel: viewModel)
                    if viewModel.hasPhysicalSymptoms {
                        MorningCheckInPhysicalSymptomsSection(
                            viewModel: viewModel,
                            showPainEntryEditor: $showPainEntryEditor,
                            editingPainEntry: $editingPainEntry
                        )
                    }
                    if viewModel.hasRespiratorySymptoms {
                        MorningCheckInRespiratorySymptomsSection(viewModel: viewModel)
                    }
                    MorningCheckInSleepEnvironmentSection(viewModel: viewModel)
                    MorningCheckInSleepTherapySection(viewModel: viewModel)
                    MorningCheckInNarcolepsySection(viewModel: viewModel)
                    MorningCheckInNotesSection(viewModel: viewModel)
                    MorningCheckInRememberSettingsSection(viewModel: viewModel)
                    MorningCheckInSubmitSection(
                        viewModel: viewModel,
                        dismissAction: { dismiss() },
                        onComplete: onComplete
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        dismiss()
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .sheet(isPresented: $showPainEntryEditor) {
                GranularPainEntryEditorView(initialEntry: editingPainEntry) { result in
                    viewModel.upsertPainEntries(result.entries, replacingEntryKey: result.replacedEntryKey)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
            Text("Good Morning!")
                .font(.title2.bold())
            Text("Quick check-in about last night's sleep")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }
}

#Preview { MorningCheckInView(sessionId: "preview-session", sessionDate: "2025-01-01") }
