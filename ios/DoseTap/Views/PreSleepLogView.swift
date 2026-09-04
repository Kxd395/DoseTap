//
//  PreSleepLogView.swift
//  DoseTap
//
//  Pre-Sleep Log: 3-card quick check-in before session
//  Designed to complete in <30 seconds with one hand
//

import DoseCore
import Foundation
import SwiftUI

// MARK: - Pre-Sleep Log View (Main Container)
struct PreSleepLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentCard = 0
    @State private var answers: PreSleepLogAnswers
    @State private var showMoreDetails = false
    @State private var rememberLastSettings: Bool
    @State private var didApplyRememberedSettings = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    
    let existingLog: StoredPreSleepLog?
    let onComplete: (PreSleepLogAnswers) throws -> Void
    let onSkip: () throws -> Void
    
    private let totalCards = 3
    private static let rememberLastSettingsKey = "preSleepLog.rememberLastSettings"
    static let maxDoseAmountMg = 20_000
    static let nightlyDoseWarningThresholdMg = 9_000
    
    init(
        existingLog: StoredPreSleepLog? = nil,
        onComplete: @escaping (PreSleepLogAnswers) throws -> Void,
        onSkip: @escaping () throws -> Void
    ) {
        self.existingLog = existingLog
        self.onComplete = onComplete
        self.onSkip = onSkip
        let initialAnswers = existingLog?.answers ?? PreSleepLogAnswers()
        _answers = State(initialValue: initialAnswers)
        _showMoreDetails = State(initialValue: Self.shouldExpandOptionalDetails(for: initialAnswers))
        _rememberLastSettings = State(initialValue: Self.rememberLastSettingsDefault())
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressBar(current: currentCard + 1, total: totalCards)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                if let plan = planSummary {
                    PlanInlineHint(plan: plan)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                rememberLastSettingsSection
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Card content
                TabView(selection: $currentCard) {
                    // Card 1: Timing + Stress
                    Card1TimingStress(answers: $answers)
                        .tag(0)
                    
                    // Card 2: Body + Substances
                    Card2BodySubstances(
                        answers: $answers,
                        medicationSessionKey: medicationSessionKey
                    )
                        .tag(1)
                    
                    // Card 3: Activity + Naps
                    Card3ActivityNaps(
                        answers: $answers,
                        showMoreDetails: $showMoreDetails
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentCard)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    // Back button (hidden on first card)
                    if currentCard > 0 {
                        Button {
                            withAnimation { currentCard -= 1 }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.headline)
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Next/Done button
                    if currentCard < totalCards - 1 {
                        Button {
                            withAnimation { currentCard += 1 }
                        } label: {
                            HStack {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    } else {
                        Button {
                            saveAndComplete()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text(existingLog == nil ? "Done" : "Save")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(existingLog == nil ? "Pre-Sleep Check" : "Edit Pre-Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if existingLog == nil {
                        Button("Skip for tonight") {
                            do {
                                try onSkip()
                                dismiss()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                                showSaveError = true
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadLastAnswers()
                    } label: {
                        Text("Use last")
                            .font(.subheadline)
                    }
                }
            }
        }
        .alert("Pre-Sleep Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            applyRememberedSettingsIfNeeded()
        }
    }
    
    private func saveAndComplete() {
        if let pain = answers.bodyPain, pain != .none, (answers.painEntries ?? []).isEmpty {
            saveErrorMessage = "Add at least one pain entry with area, side, intensity, and sensation."
            showSaveError = true
            return
        }
        if answers.hasCaffeineIntake &&
            (answers.caffeineLastIntakeAt == nil || answers.caffeineLastAmountMg == nil || answers.caffeineDailyTotalMg == nil) {
            saveErrorMessage = "Add stimulant last time, last amount, and daily total."
            showSaveError = true
            return
        }
        if answers.hasCaffeineIntake {
            let last = answers.caffeineLastAmountMg ?? 0
            let total = answers.caffeineDailyTotalMg ?? 0
            if last <= 0 {
                saveErrorMessage = "Stimulant last amount must be greater than 0 oz."
                showSaveError = true
                return
            }
            if total < last {
                saveErrorMessage = "Stimulant daily total must be at least the last amount."
                showSaveError = true
                return
            }
        }
        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none &&
            (answers.alcoholLastDrinkAt == nil || answers.alcoholLastAmountDrinks == nil || answers.alcoholDailyTotalDrinks == nil) {
            saveErrorMessage = "Add alcohol last time, last amount, and daily total."
            showSaveError = true
            return
        }
        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
            let last = answers.alcoholLastAmountDrinks ?? 0
            let total = answers.alcoholDailyTotalDrinks ?? 0
            if last <= 0 {
                saveErrorMessage = "Alcohol last amount must be greater than 0 drinks."
                showSaveError = true
                return
            }
            if total < last {
                saveErrorMessage = "Alcohol daily total must be at least the last amount."
                showSaveError = true
                return
            }
        }
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none &&
            (answers.exerciseType == nil || answers.exerciseLastAt == nil || answers.exerciseDurationMinutes == nil) {
            saveErrorMessage = "Add exercise type, last time, and duration."
            showSaveError = true
            return
        }
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none && (answers.exerciseDurationMinutes ?? 0) < 5 {
            saveErrorMessage = "Exercise duration must be at least 5 minutes."
            showSaveError = true
            return
        }
        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none &&
            (answers.napCount == nil || answers.napTotalMinutes == nil || answers.napLastEndAt == nil) {
            saveErrorMessage = "Add nap count, total minutes, and last nap end time."
            showSaveError = true
            return
        }
        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none && ((answers.napCount ?? 0) < 1 || (answers.napTotalMinutes ?? 0) < 5) {
            saveErrorMessage = "Nap count must be at least 1 and total nap time at least 5 minutes."
            showSaveError = true
            return
        }
        if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none && answers.lateMealEndedAt == nil {
            saveErrorMessage = "Add when your last late meal ended."
            showSaveError = true
            return
        }
        if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none && answers.screensLastUsedAt == nil {
            saveErrorMessage = "Add when you last used a screen in bed."
            showSaveError = true
            return
        }
        do {
            UserDefaults.standard.set(rememberLastSettings, forKey: Self.rememberLastSettingsKey)
            try onComplete(answers)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func loadLastAnswers() {
        if let lastLog = sessionRepo.fetchMostRecentCompletedPreSleepLog(),
           let lastAnswers = lastLog.answers {
            answers = lastAnswers.carriedForwardForNewNight(referenceDate: Date())
            showMoreDetails = showMoreDetails || Self.shouldExpandOptionalDetails(for: answers)
        }
    }

    private func applyRememberedSettingsIfNeeded() {
        guard existingLog == nil else { return }
        guard rememberLastSettings else { return }
        guard !didApplyRememberedSettings else { return }
        didApplyRememberedSettings = true
        loadLastAnswers()
    }

    private func toggleRememberLastSettings() {
        withAnimation {
            rememberLastSettings.toggle()
        }
        UserDefaults.standard.set(rememberLastSettings, forKey: Self.rememberLastSettingsKey)
        if rememberLastSettings {
            applyRememberedSettingsIfNeeded()
        }
    }

    static func rememberLastSettingsDefault(userDefaults: UserDefaults = .standard) -> Bool {
        if let stored = userDefaults.object(forKey: rememberLastSettingsKey) as? Bool {
            return stored
        }
        return true
    }

    private var planSummary: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)? {
        let key = sessionRepo.preSleepDisplaySessionKey(for: Date())
        let plan = sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
        return (plan.wakeBy, plan.recommendedInBed, plan.windDown, plan.expectedSleepMinutes)
    }

    private var medicationSessionKey: String {
        let referenceDate: Date
        if let timestamp = existingLog.flatMap({ AppFormatters.iso8601Fractional.date(from: $0.createdAtUtc) }) {
            referenceDate = timestamp
        } else {
            referenceDate = Date()
        }
        return sessionRepo.preSleepSessionDateKey(for: referenceDate)
    }

    private static func shouldExpandOptionalDetails(for answers: PreSleepLogAnswers) -> Bool {
        (answers.lateMeal ?? .none) != .none ||
        answers.lateMealEndedAt != nil ||
        (answers.screensInBed ?? .none) != .none ||
        answers.screensLastUsedAt != nil ||
        answers.roomTemp != nil ||
        answers.noiseLevel != nil ||
        answers.hasSleepAids ||
        !(answers.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var rememberLastSettingsSection: some View {
        HStack {
            Image(systemName: rememberLastSettings ? "checkmark.square.fill" : "square")
                .foregroundColor(rememberLastSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember last pre-sleep settings")
                    .font(.subheadline)
                Text("Auto-apply the same pre-sleep setup next time. You can still override anything.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onTapGesture {
            toggleRememberLastSettings()
        }
    }
}

extension PreSleepLogAnswers {
    func carriedForwardForNewNight(referenceDate: Date, calendar: Calendar = .current) -> PreSleepLogAnswers {
        var carried = self
        carried.caffeineLastIntakeAt = Self.carryTimeOfDay(caffeineLastIntakeAt, to: referenceDate, calendar: calendar)
        carried.alcoholLastDrinkAt = Self.carryTimeOfDay(alcoholLastDrinkAt, to: referenceDate, calendar: calendar)
        carried.exerciseLastAt = Self.carryTimeOfDay(exerciseLastAt, to: referenceDate, calendar: calendar)
        carried.napLastEndAt = Self.carryTimeOfDay(napLastEndAt, to: referenceDate, calendar: calendar)
        carried.lateMealEndedAt = Self.carryTimeOfDay(lateMealEndedAt, to: referenceDate, calendar: calendar)
        carried.screensLastUsedAt = Self.carryTimeOfDay(screensLastUsedAt, to: referenceDate, calendar: calendar)
        carried.stressNotes = nil
        carried.notes = nil
        return carried
    }

    private static func carryTimeOfDay(_ source: Date?, to referenceDate: Date, calendar: Calendar) -> Date? {
        guard let source else { return nil }
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: source)
        var carried = DateComponents()
        carried.calendar = calendar
        carried.timeZone = calendar.timeZone
        carried.year = dateComponents.year
        carried.month = dateComponents.month
        carried.day = dateComponents.day
        carried.hour = timeComponents.hour
        carried.minute = timeComponents.minute
        carried.second = timeComponents.second
        carried.nanosecond = timeComponents.nanosecond
        return calendar.date(from: carried)
    }
}

// MARK: - Preview
#Preview {
    PreSleepLogView(
        onComplete: { _ in },
        onSkip: {}
    )
}
