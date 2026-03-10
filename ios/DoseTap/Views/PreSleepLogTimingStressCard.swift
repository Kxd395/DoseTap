import DoseCore
import Foundation
import SwiftUI

// MARK: - Progress Bar
struct ProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? Color.blue : Color(.systemGray4))
                        .frame(height: 4)
                }
            }

            Text("Card \(current) of \(total)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct PlanInlineHint: View {
    let plan: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)

    private var formatter: DateFormatter {
        AppFormatters.shortTime
    }

    var body: some View {
        HStack {
            Image(systemName: "bed.double.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wake by \(formatter.string(from: plan.wakeBy))")
                    .font(.subheadline.bold())
                Text("In bed by \(formatter.string(from: plan.inBed)); wind down \(formatter.string(from: plan.windDown))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(Int(plan.expectedSleep)) min")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Card 1: Timing + Stress
struct Card1TimingStress: View {
    @Binding var answers: PreSleepLogAnswers

    private var hasStressDetails: Bool {
        answers.stressLevel != nil
            || !answers.resolvedStressDrivers.isEmpty
            || answers.stressProgression != nil
            || !(answers.stressNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var stressDriversBinding: Binding<[PreSleepLogAnswers.StressDriver]> {
        Binding(
            get: { answers.resolvedStressDrivers },
            set: { newValue in
                let sanitized = PreSleepLogAnswers.sanitizedStressDrivers(newValue)
                answers.stressDrivers = sanitized.isEmpty ? nil : sanitized
                answers.stressDriver = sanitized.first
            }
        )
    }

    private var stressNotesBinding: Binding<String> {
        Binding(
            get: { answers.stressNotes ?? "" },
            set: { answers.stressNotes = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                QuestionSection(title: "When do you plan to sleep?", icon: "bed.double.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.IntendedSleepTime.allCases,
                        selection: $answers.intendedSleepTime
                    )
                }

                QuestionSection(title: "Stress level right now?", icon: "brain.head.profile") {
                    StressSlider(value: $answers.stressLevel)
                }

                if hasStressDetails {
                    QuestionSection(title: "Current stressors?", icon: "exclamationmark.triangle") {
                        MultiSelectGrid(
                            options: PreSleepLogAnswers.StressDriver.allCases,
                            selections: stressDriversBinding
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    QuestionSection(title: "Stress trend today?", icon: "chart.line.uptrend.xyaxis") {
                        OptionGrid(
                            options: PreSleepLogAnswers.StressProgression.allCases,
                            selection: $answers.stressProgression
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    QuestionSection(title: "Stress notes", icon: "square.and.pencil") {
                        TextField(
                            "What is driving it, what helped, or what got worse?",
                            text: stressNotesBinding,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if answers.intendedSleepTime == .later {
                    QuestionSection(title: "Why later?", icon: "clock.badge.questionmark") {
                        OptionGrid(
                            options: PreSleepLogAnswers.LaterReason.allCases,
                            selection: $answers.laterReason
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.stressLevel)
            .animation(.easeInOut(duration: 0.2), value: answers.stressProgression)
            .animation(.easeInOut(duration: 0.2), value: answers.intendedSleepTime)
        }
    }
}
