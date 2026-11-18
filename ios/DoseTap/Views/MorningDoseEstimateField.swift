import SwiftUI

struct MorningDoseEstimateField: View {
    let dose: Int
    @Binding var estimate: Date?
    @State private var draft: Date?
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                DatePicker("Approximate Dose \(dose) time", selection: Binding(
                    get: { draft ?? Date() },
                    set: { draft = $0 }
                ), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("morning-dose-\(dose)-estimate-picker")
                Button("Use this estimate") {
                    guard let draft else { return }
                    estimate = Calendar.current.dateInterval(of: .minute, for: draft)?.start ?? draft
                    isEditing = false
                }
                .disabled(draft == nil)
                .accessibilityIdentifier("morning-dose-\(dose)-confirm-estimate")
                Button("Cancel estimate") { isEditing = false }
            } else if let estimate {
                Text("Estimated time: \(estimate.formatted(date: .abbreviated, time: .shortened))")
                Button("Change estimate") {
                    draft = estimate
                    isEditing = true
                }
                Button("Clear estimated time") { self.estimate = nil }
            } else {
                Button("Enter approximate time") {
                    draft = nil
                    isEditing = true
                }
                .accessibilityIdentifier("morning-dose-\(dose)-enter-estimate")
                Text("Without an estimate, this dose stays unrecorded. You can still save your morning answers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
