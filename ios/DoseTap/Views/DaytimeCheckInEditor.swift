import DoseCore
import SwiftUI

struct DaytimeCheckInEditor: View {
    let original: DaytimeCheckIn?
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var rating: Int?
    @State private var status: DaytimeCheckIn.Status?
    @State private var observedAt = Date()
    @State private var retrospective = false
    @State private var activity: DaytimeCheckIn.Activity?
    @State private var setting: DaytimeCheckIn.Setting = .unanswered
    @State private var note = ""
    @State private var reason = ""
    @State private var pending: DaytimeCheckIn?
    @State private var failure: String?

    init(original: DaytimeCheckIn? = nil, onSaved: @escaping () -> Void = {}) {
        self.original = original
        self.onSaved = onSaved
        _rating = State(initialValue: original?.response)
        _status = State(initialValue: original?.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(original == nil ? "How sleepy do you feel?" : "How sleepy did you feel then?") {
                    if let original {
                        let zone = TimeZone(secondsFromGMT: original.utcOffsetSeconds) ?? .gmt
                        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
                        LabeledContent("Original observation", value: original.assessedAt.formatted(style))
                        Text(original.timeZoneIdentifier).foregroundStyle(.secondary)
                    }
                    Text("0 means not sleepy. 10 means extremely sleepy.")
                        .font(.subheadline)
                    Text(rating.map { "Selected rating: \($0)/10" } ?? "No rating selected")
                        .font(.headline)
                        .accessibilityIdentifier("daytime-rating-summary")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 76 : 48))]) {
                        ForEach(0...10, id: \.self) { value in
                            Button {
                                if original == nil && !retrospective { observedAt = Date() }
                                rating = value
                                status = .answered
                            } label: {
                                Text(value.formatted())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Sleepiness \(value) of 10")
                            .accessibilityAddTraits(rating == value ? .isSelected : [])
                            .accessibilityIdentifier("daytime-rating-\(value)")
                        }
                    }
                    if rating != nil {
                        Button("Clear rating") { rating = nil; status = nil }
                    } else {
                        Picker("Response without a rating", selection: $status) {
                            Text("Choose a response").tag(DaytimeCheckIn.Status?.none)
                            Text("Unsure").tag(Optional(DaytimeCheckIn.Status.unsure))
                            Text("Incomplete").tag(Optional(DaytimeCheckIn.Status.incomplete))
                            Text("Skipped").tag(Optional(DaytimeCheckIn.Status.skipped))
                        }
                    }
                }
                .disabled(pending != nil)

                if original != nil {
                    Section("Reason for correction") {
                        TextField("Reason", text: $reason)
                            .accessibilityIdentifier("daytime-correction-reason")
                    }
                    .disabled(pending != nil)
                } else {
                    Section {
                        DisclosureGroup("Optional details") {
                            Toggle("Record an earlier observation", isOn: $retrospective)
                                .onChange(of: retrospective) { _ in
                                    observedAt = Date()
                                    rating = nil
                                    status = nil
                                }
                            if retrospective {
                                DatePicker("Observed at", selection: $observedAt, in: ...Date())
                            }
                            Picker("Activity", selection: $activity) {
                                Text("Not answered").tag(DaytimeCheckIn.Activity?.none)
                                ForEach(DaytimeCheckIn.Activity.allCases, id: \.self) {
                                    Text($0.rawValue).tag(Optional($0))
                                }
                            }
                            Picker("Setting", selection: $setting) {
                                ForEach(DaytimeCheckIn.Setting.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            TextField("Notes", text: $note, axis: .vertical)
                        }
                    }
                    .disabled(pending != nil)
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.circle")
                        if pending != nil {
                            Button("Edit before retry") {
                                pending = nil
                                self.failure = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "Daytime check-in" : "Correct response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending == nil ? "Save" : "Retry", action: save)
                        .disabled(status == nil || (original != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("daytime-save")
                }
            }
        }
    }

    private func save() {
        guard let status else { return }
        do {
            if pending == nil {
                let now = Date()
                if let original {
                    pending = try original.corrected(response: rating, status: status, reason: reason, recordedAt: now)
                } else {
                    pending = try DaytimeCheckIn(assessedAt: retrospective || rating != nil ? observedAt : now,
                                                 recordedAt: now, timeZoneIdentifier: TimeZone.current.identifier,
                                                 response: rating, status: status,
                                                 origin: retrospective ? .retrospective : .userInitiated,
                                                 activity: activity, setting: setting, note: note)
                }
            }
            guard let pending else { return }
            try SessionRepository.shared.saveDaytimeCheckIn(pending)
            onSaved()
            dismiss()
        } catch {
            failure = (error as? DaytimeDiaryError)?.localizedDescription
                ?? DaytimeDiaryError.notCommitted.localizedDescription
        }
    }
}
