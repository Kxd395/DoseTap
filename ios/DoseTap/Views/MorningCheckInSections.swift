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
        }
    }
}

struct MorningCheckInRememberSettingsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        HStack {
            Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square")
                .foregroundColor(viewModel.rememberSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember last wake-up settings")
                    .font(.subheadline)
                Text("Auto-prefill your last morning check-in setup next time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation {
                viewModel.setRememberSettingsEnabled(!viewModel.rememberSettings)
            }
        }
    }
}

struct MorningCheckInSubmitSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    let dismissAction: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty {
                Text("Add at least one pain entry before submitting.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let submissionErrorMessage = viewModel.submissionErrorMessage {
                Label(submissionErrorMessage, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("morning-check-in-storage-error")
            }

            Button {
                Task {
                    if await viewModel.submit() {
                        dismissAction()
                        onComplete()
                    }
                }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Complete Check-In")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.gradient)
                .cornerRadius(16)
            }
            .disabled(viewModel.isSubmitting || (viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty))
        }
        .padding(.top, 8)
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

    var body: some View {
        HStack(spacing: 12) {
            ForEach(GrogginessLevel.allCases, id: \.self) { level in
                Button {
                    viewModel.grogginess = level
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: level.icon)
                            .font(.title2)
                        Text(level.rawValue)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewModel.grogginess == level ? Color.orange.opacity(0.2) : Color.clear)
                    .foregroundColor(viewModel.grogginess == level ? .orange : .secondary)
                    .cornerRadius(8)
                }
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
    let range: ClosedRange<Int>
    let accentColor: Color
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(spacing: 8) {
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
