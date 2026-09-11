import SwiftUI
import DoseCore

/// An unanswered choice stays nil rather than displaying a default as a saved answer.
struct SleepingSetupChoice<Choice: RawRepresentable & CaseIterable & Hashable>: View where Choice.RawValue == String {
    let title: String
    let id: String
    @Binding var selection: Choice?
    var options: [Choice] = Array(Choice.allCases)
    @State private var choosing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Button { choosing = true } label: {
                HStack {
                    Text(selection?.rawValue ?? "Not recorded").fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
            .accessibilityIdentifier(id).accessibilityLabel(title)
            .accessibilityValue(selection?.rawValue ?? "Not recorded")
            .confirmationDialog(title, isPresented: $choosing, titleVisibility: .visible) {
                Button("Not recorded") { selection = nil }
                ForEach(options, id: \.self) { option in
                    Button(option.rawValue) { selection = option }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct SleepingSetupFields: View {
    @Binding var setup: SleepingSetup
    let prefix: String
    var isMorning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SleepingSetupChoice(title: isMorning ? "Who shared the sleeping space?" : "Who will share the sleeping space?", id: prefix + "-arrangement", selection: $setup.arrangement)
            if setup.needsSharedDetail {
                SleepingSetupChoice(title: "How is the space shared?", id: prefix + "-shared-space", selection: $setup.sharedSpace)
            }
            SleepingSetupChoice(title: "Pets in the sleeping space", id: prefix + "-pets", selection: $setup.pets)
            SleepingSetupChoice(title: isMorning ? "Where did you sleep?" : "Where are you sleeping?", id: prefix + "-location", selection: $setup.location)
        }
        .onChange(of: setup.arrangement) { _ in setup = setup.normalized }
    }
}

enum UsualSleepingSetupStore {
    static let key = "preSleepLog.usualSleepingSetup.v1"
    static func load(from defaults: UserDefaults = .standard) -> SleepingSetup? {
        guard let data = defaults.data(forKey: key), let setup = try? JSONDecoder().decode(SleepingSetup.self, from: data),
              setup.version == 1, !setup.isEmpty else { return nil }
        return setup.normalized
    }
    @discardableResult static func save(_ setup: SleepingSetup, to defaults: UserDefaults = .standard) -> Bool {
        guard !setup.isEmpty, let data = try? JSONEncoder().encode(setup.normalized) else { return false }
        defaults.set(data, forKey: key)
        return load(from: defaults) == setup.normalized
    }
}

struct PreSleepSleepingSetupSection: View {
    @Binding var answers: PreSleepLogAnswers
    var allowRememberedSetup = true
    @State private var usual: SleepingSetup?
    @State private var feedback: String?
    private var setup: Binding<SleepingSetup> {
        Binding(get: { answers.sleepingSetup ?? SleepingSetup() }, set: {
            answers.sleepingSetup = $0.isEmpty ? nil : $0.normalized
        })
    }
    var body: some View {
        QuestionSection(title: "Sleeping arrangement", icon: "bed.double.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your plan for this sleep period. Every question is optional; no names or addresses are needed.")
                    .font(.footnote).foregroundStyle(.secondary)
                SleepingSetupFields(setup: setup, prefix: "pre-sleeping")
                if allowRememberedSetup {
                    if let usual {
                        Text("Usual setup: \(usual.summary)").font(.footnote)
                        Button("Use usual sleeping setup") {
                            setup.wrappedValue = setup.wrappedValue.applyingMissing(from: usual)
                            feedback = "Usual setup applied to unanswered fields. Review your plan before saving."
                        }.accessibilityIdentifier("pre-use-usual-sleeping")
                    }
                    Button("Save as usual setup") {
                        if UsualSleepingSetupStore.save(setup.wrappedValue) {
                            usual = UsualSleepingSetupStore.load()
                            feedback = "Usual setup saved. Finish the check-in to save tonight's plan."
                        } else { feedback = "Could not save the usual setup. Your answers are still here; try again." }
                    }
                    .disabled(setup.wrappedValue.isEmpty).accessibilityIdentifier("pre-save-usual-sleeping")
                    if usual != nil {
                        Button("Forget usual setup", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: UsualSleepingSetupStore.key)
                            usual = nil; feedback = "Usual setup forgotten. This night's answers and past records are unchanged."
                        }
                    }
                    if let feedback { Text(feedback).font(.footnote).accessibilityIdentifier("pre-sleeping-feedback") }
                }
            }
        }.onAppear { if allowRememberedSetup { usual = UsualSleepingSetupStore.load() } }
    }
}

struct MorningSleepingSetupSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    private var context: Binding<MorningSleepingContext> { $viewModel.sleepingContext }
    private var confirmation: Binding<MorningSleepingContext.Confirmation?> {
        Binding(get: { viewModel.sleepingContext.confirmation }, set: { viewModel.sleepingContext.selectConfirmation($0) })
    }
    private var actual: Binding<SleepingSetup> {
        Binding(get: { viewModel.sleepingContext.actual ?? SleepingSetup() }, set: {
            viewModel.sleepingContext.actual = $0.isEmpty ? nil : $0.normalized
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sleeping arrangement", systemImage: "bed.double.fill").font(.headline)
            if let plan = viewModel.sleepingContext.plan, !plan.isEmpty {
                Text("Planned: \(plan.summary)").font(.footnote)
            } else { Text("No planned sleeping setup recorded for this night. You can still enter what happened.").font(.footnote) }
            SleepingSetupChoice(title: "Was your sleeping arrangement the same as planned?", id: "morning-sleeping-confirmation",
                selection: confirmation, options: MorningSleepingContext.Confirmation.allCases.filter {
                    $0 != .same || viewModel.sleepingContext.plan?.isEmpty == false
                })
            if viewModel.sleepingContext.confirmation == .changed {
                Text("What was your actual sleeping setup?").font(.subheadline.bold())
                SleepingSetupFields(setup: actual, prefix: "morning-sleeping", isMorning: true)
            } else if let actual = viewModel.sleepingContext.actual {
                Text("Confirmed: \(actual.summary)").font(.footnote).accessibilityIdentifier("morning-sleeping-confirmed")
            }
            SleepingSetupChoice(title: "Did sharing the sleeping space affect your sleep? (Optional)", id: "morning-sleeping-impact", selection: context.impact)
            if viewModel.sleepingContext.allowsFactors {
                Text("What helped or disrupted sleep? Select any that apply.").font(.subheadline)
                ForEach(MorningSleepingContext.Factor.allCases, id: \.self) { factor in
                    Toggle(factor.rawValue, isOn: Binding(get: { viewModel.sleepingContext.factors?.contains(factor) == true }, set: { selected in
                        var values = viewModel.sleepingContext.factors ?? []
                        values.removeAll { $0 == factor }; if selected { values.append(factor) }
                        viewModel.sleepingContext.factors = values.isEmpty ? nil : values
                    }))
                }
            }
            Text("These answers describe this sleep period only. They do not change your usual setup.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: viewModel.sleepingContext.impact) { _ in
            if !viewModel.sleepingContext.allowsFactors { viewModel.sleepingContext.factors = nil }
        }
    }
}
