import DoseCore
import Foundation
import SwiftUI

// MARK: - Card 3: Activity + Naps + Optional More Details
struct Card3ActivityNaps: View {
    @Binding var answers: PreSleepLogAnswers
    @Binding var showMoreDetails: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                QuestionSection(title: "Exercise today?", icon: "figure.run") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.ExerciseLevel.allCases,
                            selection: $answers.exercise
                        )
                        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none {
                            SubstanceDetailCard(title: "Exercise Details") {
                                Picker("Type", selection: Binding(get: {
                                    answers.exerciseType ?? defaultExerciseType()
                                }, set: { answers.exerciseType = $0 })) {
                                    ForEach(PreSleepLogAnswers.ExerciseType.allCases, id: \.self) { type in
                                        Text(type.displayText).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                SubstanceTimePickerRow(
                                    label: "Last exercise time",
                                    value: Binding(
                                        get: { answers.exerciseLastAt ?? defaultExerciseLastAt() },
                                        set: { answers.exerciseLastAt = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Duration",
                                    unit: "min",
                                    range: 5...600,
                                    step: 5,
                                    value: Binding(
                                        get: { answers.exerciseDurationMinutes ?? defaultExerciseDurationMinutes() },
                                        set: { answers.exerciseDurationMinutes = $0 }
                                    )
                                )
                            }
                        }
                    }
                }

                QuestionSection(title: "Nap today?", icon: "moon.zzz.fill") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.NapDuration.allCases,
                            selection: $answers.napToday
                        )
                        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none {
                            SubstanceDetailCard(title: "Nap Details") {
                                SubstanceIntStepperRow(
                                    label: "Nap count",
                                    unit: "naps",
                                    range: 1...6,
                                    step: 1,
                                    value: Binding(
                                        get: { answers.napCount ?? 1 },
                                        set: { answers.napCount = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Total nap time",
                                    unit: "min",
                                    range: 5...360,
                                    step: 5,
                                    value: Binding(
                                        get: { answers.napTotalMinutes ?? defaultNapTotalMinutes() },
                                        set: { answers.napTotalMinutes = $0 }
                                    )
                                )
                                SubstanceTimePickerRow(
                                    label: "Last nap ended",
                                    value: Binding(
                                        get: { answers.napLastEndAt ?? defaultNapLastEndAt() },
                                        set: { answers.napLastEndAt = $0 }
                                    )
                                )
                            }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                Toggle(isOn: $showMoreDetails) {
                    Label("Add more details", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .tint(.blue)

                if showMoreDetails {
                    Group {
                        QuestionSection(title: "Late meal?", icon: "fork.knife") {
                            VStack(spacing: 10) {
                                OptionGrid(
                                    options: PreSleepLogAnswers.LateMeal.allCases,
                                    selection: $answers.lateMeal
                                )
                                if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none {
                                    SubstanceDetailCard(title: "Meal Timing") {
                                        SubstanceTimePickerRow(
                                            label: "Last meal ended",
                                            value: Binding(
                                                get: { answers.lateMealEndedAt ?? defaultLateMealEndedAt() },
                                                set: { answers.lateMealEndedAt = $0 }
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        QuestionSection(title: "Screens in bed?", icon: "iphone") {
                            VStack(spacing: 10) {
                                OptionGrid(
                                    options: PreSleepLogAnswers.ScreensInBed.allCases,
                                    selection: $answers.screensInBed
                                )
                                if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none {
                                    SubstanceDetailCard(title: "Screen Timing") {
                                        SubstanceTimePickerRow(
                                            label: "Last used in bed",
                                            value: Binding(
                                                get: { answers.screensLastUsedAt ?? defaultScreensLastUsedAt() },
                                                set: { answers.screensLastUsedAt = $0 }
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        QuestionSection(title: "Room temperature?", icon: "thermometer.medium") {
                            OptionGrid(
                                options: PreSleepLogAnswers.RoomTemp.allCases,
                                selection: $answers.roomTemp
                            )
                        }

                        QuestionSection(title: "Noise level?", icon: "speaker.wave.2") {
                            OptionGrid(
                                options: PreSleepLogAnswers.NoiseLevel.allCases,
                                selection: $answers.noiseLevel
                            )
                        }

                        QuestionSection(title: "Sleep aids?", icon: "moon.stars") {
                            VStack(spacing: 12) {
                                HStack(alignment: .top) {
                                    Text("Select every aid you used.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if answers.hasSleepAids {
                                        Button("Clear") {
                                            clearSleepAidSelections()
                                        }
                                        .font(.caption.weight(.semibold))
                                    }
                                }

                                MultiSelectGrid(
                                    options: PreSleepLogAnswers.sleepAidOptions,
                                    selections: Binding(
                                        get: { answers.resolvedSleepAidSelections },
                                        set: { updateSleepAidSelections($0) }
                                    )
                                )

                                if answers.hasLegacyUnspecifiedSleepAids {
                                    Text("Older entry saved as multiple sleep aids. Leave it as-is or reselect the exact aids now.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if answers.hasSleepAids {
                                    SubstanceDetailCard(title: sleepAidDetailTitle) {
                                        Text("Track combinations like fan plus earplugs without collapsing them into one vague bucket.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }

                        QuestionSection(title: "Anything else?", icon: "square.and.pencil") {
                            TextField("Notes about today, routines, symptoms, or setup", text: Binding(
                                get: { answers.notes ?? "" },
                                set: { answers.notes = $0 }
                            ), axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showMoreDetails)
        }
        .onChange(of: answers.exercise) { newValue in
            if (newValue ?? PreSleepLogAnswers.ExerciseLevel.none) == PreSleepLogAnswers.ExerciseLevel.none {
                answers.exerciseType = nil
                answers.exerciseLastAt = nil
                answers.exerciseDurationMinutes = nil
            } else {
                if answers.exerciseType == nil { answers.exerciseType = defaultExerciseType() }
                if answers.exerciseLastAt == nil { answers.exerciseLastAt = defaultExerciseLastAt() }
                if answers.exerciseDurationMinutes == nil { answers.exerciseDurationMinutes = defaultExerciseDurationMinutes() }
                normalizeExerciseDetails()
            }
        }
        .onChange(of: answers.exerciseDurationMinutes) { _ in
            normalizeExerciseDetails()
        }
        .onChange(of: answers.napToday) { newValue in
            if (newValue ?? PreSleepLogAnswers.NapDuration.none) == PreSleepLogAnswers.NapDuration.none {
                answers.napCount = nil
                answers.napTotalMinutes = nil
                answers.napLastEndAt = nil
            } else {
                if answers.napCount == nil { answers.napCount = 1 }
                if answers.napTotalMinutes == nil { answers.napTotalMinutes = defaultNapTotalMinutes() }
                if answers.napLastEndAt == nil { answers.napLastEndAt = defaultNapLastEndAt() }
                normalizeNapDetails()
            }
        }
        .onChange(of: answers.napCount) { _ in
            normalizeNapDetails()
        }
        .onChange(of: answers.napTotalMinutes) { _ in
            normalizeNapDetails()
        }
        .onChange(of: answers.lateMeal) { newValue in
            if (newValue ?? PreSleepLogAnswers.LateMeal.none) == .none {
                answers.lateMealEndedAt = nil
            } else if answers.lateMealEndedAt == nil {
                answers.lateMealEndedAt = defaultLateMealEndedAt()
            }
        }
        .onChange(of: answers.screensInBed) { newValue in
            if (newValue ?? PreSleepLogAnswers.ScreensInBed.none) == .none {
                answers.screensLastUsedAt = nil
            } else if answers.screensLastUsedAt == nil {
                answers.screensLastUsedAt = defaultScreensLastUsedAt()
            }
        }
        .onAppear {
            bootstrapActivityDetailsIfNeeded()
            bootstrapOptionalDetailsIfNeeded()
        }
    }

    private func defaultExerciseType() -> PreSleepLogAnswers.ExerciseType {
        switch answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none {
        case .none: return .walking
        case .light: return .walking
        case .moderate: return .cardio
        case .intense: return .strength
        }
    }

    private func defaultExerciseLastAt() -> Date {
        Date().addingTimeInterval(-4 * 3600)
    }

    private func defaultExerciseDurationMinutes() -> Int {
        switch answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none {
        case .none: return 5
        case .light: return 20
        case .moderate: return 40
        case .intense: return 60
        }
    }

    private func defaultNapTotalMinutes() -> Int {
        switch answers.napToday ?? PreSleepLogAnswers.NapDuration.none {
        case .none: return 5
        case .short: return 20
        case .medium: return 45
        case .long: return 90
        }
    }

    private func defaultNapLastEndAt() -> Date {
        Date().addingTimeInterval(-6 * 3600)
    }

    private func defaultLateMealEndedAt() -> Date {
        Date().addingTimeInterval(-2 * 3600)
    }

    private func defaultScreensLastUsedAt() -> Date {
        Date().addingTimeInterval(-45 * 60)
    }

    private var sleepAidDetailTitle: String {
        guard let aids = answers.sleepAidDisplayText, !aids.isEmpty else {
            return "Sleep Aid Details"
        }
        return "Sleep Aid Details: \(aids)"
    }

    private func updateSleepAidSelections(_ selections: [PreSleepLogAnswers.SleepAid]) {
        let sanitized = PreSleepLogAnswers.sanitizedSleepAidSelections(selections)
        answers.sleepAidSelections = sanitized.isEmpty ? nil : sanitized
        answers.sleepAids = sanitized.isEmpty
            ? PreSleepLogAnswers.SleepAid.none
            : PreSleepLogAnswers.sleepAidSummary(for: sanitized)
    }

    private func clearSleepAidSelections() {
        answers.sleepAidSelections = nil
        answers.sleepAids = PreSleepLogAnswers.SleepAid.none
    }

    private func normalizeExerciseDetails() {
        guard (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none else { return }
        if let duration = answers.exerciseDurationMinutes {
            answers.exerciseDurationMinutes = max(5, min(600, duration))
        }
    }

    private func normalizeNapDetails() {
        guard (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none else { return }
        if let count = answers.napCount {
            answers.napCount = max(1, min(6, count))
        }
        if let total = answers.napTotalMinutes {
            answers.napTotalMinutes = max(5, min(360, total))
        }
    }

    private func bootstrapActivityDetailsIfNeeded() {
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none {
            if answers.exerciseType == nil { answers.exerciseType = defaultExerciseType() }
            if answers.exerciseLastAt == nil { answers.exerciseLastAt = defaultExerciseLastAt() }
            if answers.exerciseDurationMinutes == nil { answers.exerciseDurationMinutes = defaultExerciseDurationMinutes() }
            normalizeExerciseDetails()
        }

        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none {
            if answers.napCount == nil { answers.napCount = 1 }
            if answers.napTotalMinutes == nil { answers.napTotalMinutes = defaultNapTotalMinutes() }
            if answers.napLastEndAt == nil { answers.napLastEndAt = defaultNapLastEndAt() }
            normalizeNapDetails()
        }
    }

    private func bootstrapOptionalDetailsIfNeeded() {
        if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none, answers.lateMealEndedAt == nil {
            answers.lateMealEndedAt = defaultLateMealEndedAt()
        }

        if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none, answers.screensLastUsedAt == nil {
            answers.screensLastUsedAt = defaultScreensLastUsedAt()
        }

        if answers.sleepAidSelections == nil {
            let resolved = answers.resolvedSleepAidSelections
            answers.sleepAidSelections = resolved.isEmpty ? nil : resolved
            if !resolved.isEmpty {
                answers.sleepAids = PreSleepLogAnswers.sleepAidSummary(for: resolved)
            }
        }
    }
}
