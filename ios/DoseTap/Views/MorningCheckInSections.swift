//
//  MorningCheckInSections.swift
//  DoseTap
//

import SwiftUI
import DoseCore

struct MorningCheckInNotesSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            TextField("Anything else to note?", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("morning-check-in-notes")
        }
    }
}

struct MorningCheckInRememberSettingsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Button { withAnimation { viewModel.setRememberSettingsEnabled(!viewModel.rememberSettings) } } label: {
            HStack {
                Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square")
                    .foregroundColor(viewModel.rememberSettings ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember room and equipment setup")
                        .font(.subheadline)
                    Text("Save room temperature, noise, sleep aid and therapy-device choices when this check-in saves. Symptoms, severity, sleep results and actual sleeping arrangement need a fresh answer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain).accessibilityIdentifier("morning-remember-setup")
        .accessibilityValue(viewModel.rememberSettings ? "On" : "Off")
        .accessibilityAddTraits(viewModel.rememberSettings ? .isSelected : [])
    }
}

struct MorningCheckInSubmitSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    let dismissAction: () -> Void
    let onComplete: () -> Void
    var statusMaximumHeight: CGFloat? = nil
    @State private var showReminderWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.submissionErrorMessage != nil || viewModel.reminderCancellationWarning != nil {
                if let statusMaximumHeight {
                    ScrollView { submissionStatus }
                        .frame(maxHeight: statusMaximumHeight)
                        .accessibilityIdentifier("morning-check-in-status")
                } else {
                    submissionStatus
                }
            }

            Button {
                Task {
                    if await viewModel.submit() {
                        if viewModel.reminderCancellationWarning != nil {
                            showReminderWarning = true
                        } else {
                            dismissAction()
                            onComplete()
                        }
                    }
                }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text(viewModel.isHistory ? "Review History Answers" : "Complete Check-In")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.gradient)
                .cornerRadius(16)
            }
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("morning-check-in-submit")
            .layoutPriority(1)
        }
        .padding(.top, 8)
        .alert("Check-in saved; check dose reminder", isPresented: $showReminderWarning) {
            Button("Close") { dismissAction(); onComplete() }
        } message: {
            Text(viewModel.reminderCancellationWarning ?? "Check DoseTap's alarm status in Settings.")
        }
    }

    private var submissionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let submissionErrorMessage = viewModel.submissionErrorMessage {
                Label(submissionErrorMessage, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("morning-check-in-storage-error")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = viewModel.reminderCancellationWarning {
                Label(warning, systemImage: "bell.badge")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MorningCheckInSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            content
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MorningCheckInDoseStatusRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct MorningCheckInRestedPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("Rested", selection: $viewModel.feelRested) {
            ForEach(RestedLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInGrogginessPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : GrogginessLevel.allCases.count), spacing: 12) {
            ForEach(GrogginessLevel.allCases, id: \.self) { level in
                Button {
                    viewModel.grogginess = level
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: level.icon)
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(level.rawValue)
                            .font(.caption2)
                        QuestionnaireSelectionMark(isSelected: viewModel.grogginess == level)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewModel.grogginess == level ? Color.orange.opacity(0.2) : Color.clear)
                    .foregroundColor(viewModel.grogginess == level ? .primary : .secondary)
                    .cornerRadius(8)
                }
                .accessibilityLabel(Text("Grogginess: \(level.rawValue)"))
                .accessibilityValue(viewModel.grogginess == level ? "Selected" : "Not selected")
                .accessibilityAddTraits(viewModel.grogginess == level ? .isSelected : [])
                .accessibilityIdentifier("morning-grogginess-\(level.rawValue)")
            }
        }
    }
}

struct MorningCheckInCongestionPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("", selection: $viewModel.congestion) {
            ForEach(CongestionType.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInThroatPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("", selection: $viewModel.throatCondition) {
            ForEach(ThroatCondition.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInScoreSlider: View {
    @Binding var value: Int
    let questionLabel: LocalizedStringKey
    let accessibilityID: String
    let range: ClosedRange<Int>
    let accentColor: Color
    let lowLabel: String
    let highLabel: String
    var showsQuestionLabel = true

    var body: some View {
        VStack(spacing: 8) {
            if showsQuestionLabel {
                Text(questionLabel)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(lowLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)/\(range.upperBound)")
                    .font(.headline)
                Spacer()
                Text(highLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(accentColor)
            .accessibilityLabel(Text(questionLabel))
            .accessibilityValue(Text("\(value) out of \(range.upperBound)"))
            .accessibilityIdentifier(accessibilityID)
        }
    }
}

func morningCheckInOptionalBinding<T>(
    _ viewModel: MorningCheckInViewModel,
    _ keyPath: ReferenceWritableKeyPath<MorningCheckInViewModel, T>
) -> Binding<T?> {
    Binding<T?>(
        get: { .some(viewModel[keyPath: keyPath]) },
        set: { newValue in
            guard let newValue else { return }
            viewModel[keyPath: keyPath] = newValue
        }
    )
}
