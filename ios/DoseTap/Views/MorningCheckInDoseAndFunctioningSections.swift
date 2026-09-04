//
//  MorningCheckInDoseAndFunctioningSections.swift
//  DoseTap
//

import SwiftUI
import DoseCore

struct MorningCheckInQuickModeSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 20) {
            MorningCheckInSectionCard(title: "Sleep Quality", icon: "star.fill") {
                MorningCheckInSleepQualityPicker(value: $viewModel.sleepQuality)
            }

            MorningCheckInSectionCard(title: "How Rested Do You Feel?", icon: "battery.100") {
                MorningCheckInRestedPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Morning Grogginess", icon: "cloud.sun.fill") {
                MorningCheckInGrogginessPicker(viewModel: viewModel)
            }
        }
    }
}

struct MorningCheckInSleepQualityPicker: View {
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FractionalStarRow(value: value)

                Spacer(minLength: 12)

                Text("\(AppFormatters.compactRating(value))/5")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.primary)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { value = Self.normalized($0) }
                ),
                in: 1...5,
                step: 0.25
            )
            .tint(.yellow)
            .accessibilityLabel("Sleep quality")
            .accessibilityValue("\(AppFormatters.compactRating(value)) out of 5")
        }
        .padding(.vertical, 8)
    }

    private static func normalized(_ rawValue: Double) -> Double {
        min(5, max(1, (rawValue * 4).rounded() / 4))
    }
}

private struct FractionalStarRow: View {
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                FractionalStar(fill: min(1, max(0, value - Double(index))))
            }
        }
    }
}

private struct FractionalStar: View {
    let fill: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "star")
                .foregroundColor(.gray.opacity(0.3))

            GeometryReader { proxy in
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .clipped()
                    .frame(width: proxy.size.width * fill, alignment: .leading)
                    .clipped()
            }
        }
        .font(.title2)
        .frame(width: 28, height: 28)
    }
}

struct MorningCheckInDoseReconciliationSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Dose Confirmation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Dose 1", icon: "1.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose1Time = viewModel.loggedDose1Time {
                        MorningCheckInDoseStatusRow(
                            title: "Logged overnight",
                            detail: "Dose 1 was already recorded at \(AppFormatters.shortTime.string(from: loggedDose1Time))."
                        )
                    } else {
                        Toggle("I took Dose 1 but missed the tap", isOn: $viewModel.reconcileDose1Taken)
                        if viewModel.reconcileDose1Taken {
                            DatePicker(
                                "Approximate Dose 1 time",
                                selection: $viewModel.reconcileDose1Time,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            Stepper(value: $viewModel.reconcileDose1AmountMg, in: 250...20_000, step: 250) {
                                HStack {
                                    Text("Dose 1 amount")
                                    Spacer()
                                    Text("\(viewModel.reconcileDose1AmountMg.formatted(.number.grouping(.automatic))) mg")
                                        .foregroundColor(.secondary)
                                }
                            }
                            if viewModel.reconcileDose1NeedsWarning {
                                Text("Dose 1 amount is above 9,000 mg. Double-check before saving.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        } else {
                            MorningCheckInDoseStatusRow(
                                title: "No backfill selected",
                                detail: "Leave this off if Dose 1 was not taken or if you want to keep the session incomplete."
                            )
                        }
                    }
                }
            }

            MorningCheckInSectionCard(title: "Dose 2", icon: "2.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose2Time = viewModel.loggedDose2Time {
                        MorningCheckInDoseStatusRow(
                            title: "Logged overnight",
                            detail: "Dose 2 was already recorded at \(AppFormatters.shortTime.string(from: loggedDose2Time))."
                        )
                    } else {
                        Picker("Dose 2 status", selection: $viewModel.dose2Reconciliation) {
                            ForEach(Dose2ReconciliationChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch viewModel.dose2Reconciliation {
                        case .leaveAsIs:
                            MorningCheckInDoseStatusRow(
                                title: "Leave unchanged",
                                detail: "Use this if you do not want morning check-in to change Dose 2 for this session."
                            )
                        case .taken:
                            DatePicker(
                                "Approximate Dose 2 time",
                                selection: $viewModel.reconcileDose2Time,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            Stepper(value: $viewModel.reconcileDose2AmountMg, in: 250...20_000, step: 250) {
                                HStack {
                                    Text("Dose 2 amount")
                                    Spacer()
                                    Text("\(viewModel.reconcileDose2AmountMg.formatted(.number.grouping(.automatic))) mg")
                                        .foregroundColor(.secondary)
                                }
                            }
                            if viewModel.reconcileDose2NeedsWarning {
                                Text("Dose 2 amount is above 9,000 mg. Double-check before saving.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        case .skipped:
                            MorningCheckInDoseStatusRow(
                                title: "Mark Dose 2 skipped",
                                detail: "Morning check-in will keep this session complete and record that Dose 2 was skipped."
                            )
                        }
                    }

                    if viewModel.showsDose2TakenReason {
                        Divider()
                        Text("Why was Dose 2 early, late, or unusual?")
                            .font(.subheadline.weight(.semibold))
                        OptionGrid(
                            options: Dose2TakenReason.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.dose2TakenReason)
                        )
                    }

                    if viewModel.showsDose2SkippedReason {
                        Divider()
                        Text("Why was Dose 2 skipped?")
                            .font(.subheadline.weight(.semibold))
                        OptionGrid(
                            options: Dose2SkippedReason.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.dose2SkippedReason)
                        )
                    }

                    if viewModel.showsDose2TakenReason || viewModel.showsDose2SkippedReason {
                        TextField(
                            "Dose 2 reason notes (optional)",
                            text: $viewModel.dose2ReasonNotes,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    }

                    Text("Approximate times are fine here. Use this when you forgot to tap the dose button overnight.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct MorningCheckInMorningFunctioningSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Morning Functioning")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Sleep Inertia", icon: "timer") {
                OptionGrid(
                    options: SleepInertiaDuration.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.sleepInertiaDuration)
                )
            }

            MorningCheckInSectionCard(title: "Mental Clarity", icon: "lightbulb.max.fill") {
                MorningCheckInScoreSlider(
                    value: $viewModel.mentalClarity,
                    range: 1...5,
                    accentColor: .yellow,
                    lowLabel: "Foggy",
                    highLabel: "Clear"
                )
            }

            MorningCheckInSectionCard(title: "Mood", icon: "face.smiling") {
                OptionGrid(
                    options: MoodLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.mood)
                )
            }

            MorningCheckInSectionCard(title: "Anxiety", icon: "heart.text.square") {
                OptionGrid(
                    options: AnxietyLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.anxietyLevel)
                )
            }

            MorningCheckInSectionCard(title: "Stress Level", icon: "brain.head.profile") {
                StressSlider(value: $viewModel.stressLevel)
            }

            if viewModel.stressLevel != nil || !viewModel.stressDrivers.isEmpty || viewModel.stressProgression != nil || !viewModel.stressNotes.isEmpty {
                MorningCheckInSectionCard(title: "Current Stressors", icon: "exclamationmark.triangle") {
                    MultiSelectGrid(
                        options: PreSleepLogAnswers.StressDriver.allCases,
                        selections: $viewModel.stressDrivers
                    )
                }

                MorningCheckInSectionCard(title: "Stress Trend Since Bedtime", icon: "chart.line.uptrend.xyaxis") {
                    OptionGrid(
                        options: PreSleepLogAnswers.StressProgression.allCases,
                        selection: Binding(
                            get: { viewModel.stressProgression },
                            set: { viewModel.stressProgression = $0 }
                        )
                    )
                }

                MorningCheckInSectionCard(title: "Stress Notes", icon: "square.and.pencil") {
                    TextField(
                        "What is driving it, what helped, or what worsened overnight?",
                        text: $viewModel.stressNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                }
            }

            MorningCheckInSectionCard(title: "Readiness For The Day", icon: "figure.walk") {
                MorningCheckInScoreSlider(
                    value: $viewModel.readinessForDay,
                    range: 1...5,
                    accentColor: .green,
                    lowLabel: "Barely",
                    highLabel: "Ready"
                )
            }

            MorningCheckInSectionCard(title: "Dream Recall", icon: "sparkles") {
                OptionGrid(
                    options: DreamRecallType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.dreamRecall)
                )
            }
        }
    }
}
