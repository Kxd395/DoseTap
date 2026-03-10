import SwiftUI
import DoseCore

struct SelectedDayView: View {
    let date: Date
    var refreshTrigger: Bool = false
    var onDeleteRequested: (() -> Void)? = nil

    @ObservedObject private var settings = UserSettingsManager.shared
    @StateObject private var healthKit = HealthKitService.shared
    @State private var events: [StoredSleepEvent] = []
    @State private var doseLog: StoredDoseLog?
    @State private var doseEvents: [DoseCore.StoredDoseEvent] = []
    @State private var healthSleepRangeText: String?
    @State private var healthSleepStatusText: String?
    @State private var healthSleepSourceText: String?
    @State private var editingDose1 = false
    @State private var editingDose2 = false
    @State private var editingEvent: StoredSleepEvent?
    @State private var eventToDelete: StoredSleepEvent?

    private let sessionRepo = SessionRepository.shared

    private var hasData: Bool {
        doseLog != nil || !events.isEmpty
    }

    private struct NapIntervalDisplay: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date?
        let durationMinutes: Int?
    }

    private var napIntervals: [NapIntervalDisplay] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var intervals: [NapIntervalDisplay] = []
        var pendingStart: Date?

        for event in sorted {
            guard let kind = napEventKind(event.eventType) else { continue }
            if kind == "start" {
                pendingStart = event.timestamp
            } else if kind == "end", let start = pendingStart {
                let minutes = TimeIntervalMath.minutesBetween(start: start, end: event.timestamp)
                intervals.append(NapIntervalDisplay(start: start, end: event.timestamp, durationMinutes: minutes))
                pendingStart = nil
            }
        }

        if let start = pendingStart {
            intervals.append(NapIntervalDisplay(start: start, end: nil, durationMinutes: nil))
        }

        return intervals
    }

    private var sessionDateString: String {
        sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateTitle)
                    .font(.headline)
                Spacer()
                if hasData {
                    Text("Tap to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if hasData, let onDelete = onDeleteRequested {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health Cross-Check")
                    .font(.subheadline.bold())
                Text("Session key: \(sessionDateString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let healthSleepRangeText {
                    Text("Sleep range: \(healthSleepRangeText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let healthSleepSourceText {
                    Text(healthSleepSourceText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let healthSleepStatusText {
                    Text(healthSleepStatusText)
                        .font(.caption)
                        .foregroundColor(healthSleepStatusText.hasPrefix("Matches") ? .green : .orange)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )

            if let dose = doseLog {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        editingDose1 = true
                    } label: {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.green)
                            Text("Dose 1")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(dose.dose1Time.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)

                    if let dose2Time = dose.dose2Time {
                        Button {
                            editingDose2 = true
                        } label: {
                            HStack {
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(.green)
                                Text("Dose 2")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(dose2Time.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(.secondary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.plain)

                        let interval = TimeIntervalMath.minutesBetween(start: dose.dose1Time, end: dose2Time)
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("Interval")
                            Spacer()
                            Text(TimeIntervalMath.formatMinutes(interval))
                                .foregroundColor(.secondary)
                        }
                    } else if dose.skipped {
                        HStack {
                            Image(systemName: "2.circle")
                                .foregroundColor(.orange)
                            Text("Dose 2")
                            Spacer()
                            Text("Skipped")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }

            if doseLog != nil {
                DoseIntervalsCard(doseEvents: doseEvents)
            }

            if !events.isEmpty {
                Text("Events (\(events.count))")
                    .font(.subheadline.bold())
                    .padding(.top, 8)

                ForEach(events, id: \.id) { event in
                    Button {
                        editingEvent = event
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(EventDisplayName.displayName(for: event.eventType))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            editingEvent = event
                        } label: {
                            Label("Edit Time", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            eventToDelete = event
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    }
                }
            } else {
                Text("No events logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !napIntervals.isEmpty {
                Text("Naps")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                ForEach(napIntervals) { nap in
                    HStack(spacing: 10) {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(napLabel(for: nap))
                                .font(.subheadline)
                            Text(napDetail(for: nap))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onChange(of: date) { _ in loadData() }
        .onChange(of: refreshTrigger) { _ in loadData() }
        .onAppear { loadData() }
        .sheet(isPresented: $editingDose1) {
            if let dose = doseLog {
                EditDoseTimeView(
                    doseNumber: 1,
                    originalTime: dose.dose1Time,
                    dose1Time: nil,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose1Time(newTime)
                    }
                )
            }
        }
        .sheet(isPresented: $editingDose2) {
            if let dose = doseLog, let dose2Time = dose.dose2Time {
                EditDoseTimeView(
                    doseNumber: 2,
                    originalTime: dose2Time,
                    dose1Time: dose.dose1Time,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose2Time(newTime)
                    }
                )
            }
        }
        .sheet(item: $editingEvent) { event in
            EditEventTimeView(
                event: event,
                sessionDate: sessionDateString,
                onSave: { newTime in
                    saveEventTime(event: event, newTime: newTime)
                }
            )
        }
        .alert("Delete Event?", isPresented: Binding<Bool>(
            get: { eventToDelete != nil },
            set: { if !$0 { eventToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { eventToDelete = nil }
            Button("Delete", role: .destructive) {
                if let event = eventToDelete {
                    sessionRepo.deleteSleepEvent(id: event.id)
                    loadData()
                }
                eventToDelete = nil
            }
        } message: {
            if let event = eventToDelete {
                Text("Delete \"\(EventDisplayName.displayName(for: event.eventType))\" at \(event.timestamp.formatted(date: .omitted, time: .shortened))?")
            }
        }
    }

    private var dateTitle: String {
        AppFormatters.weekdayMedium.string(from: eveningAnchorDate(for: date))
    }

    private func loadData() {
        let sessionDate = sessionDateString
        events = sessionRepo.fetchSleepEvents(for: sessionDate)
        doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
        doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
        loadHealthCrossCheck(for: sessionDate)
    }

    private func saveDose1Time(_ newTime: Date) {
        sessionRepo.updateDose1Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }

    private func saveDose2Time(_ newTime: Date) {
        sessionRepo.updateDose2Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }

    private func saveEventTime(event: StoredSleepEvent, newTime: Date) {
        sessionRepo.updateEventTime(eventId: event.id, newTime: newTime)
        loadData()
    }

    private func loadHealthCrossCheck(for sessionDate: String) {
        healthSleepRangeText = nil
        healthSleepSourceText = nil
        healthSleepStatusText = nil

        Task { @MainActor in
            guard settings.healthKitEnabled else {
                healthSleepStatusText = "Apple Health disabled in Settings."
                return
            }

            healthKit.checkAuthorizationStatus()
            guard healthKit.isAuthorized else {
                healthSleepStatusText = "Apple Health not authorized."
                return
            }

            guard let nightDate = AppFormatters.sessionDate.date(from: sessionDate) else {
                healthSleepStatusText = "Unable to parse session date."
                return
            }

            let queryStart = eveningAnchorDate(for: nightDate, hour: 18)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else {
                healthSleepStatusText = "Unable to compute Apple Health query window."
                return
            }
            let queryEnd = eveningAnchorDate(for: nextDay, hour: 12)

            do {
                let segments = try await healthKit.fetchSegmentsForTimeline(from: queryStart, to: queryEnd)
                guard !segments.isEmpty else {
                    healthSleepStatusText = "No Apple Health sleep samples in this night window."
                    return
                }

                let start = segments.map(\.start).min() ?? queryStart
                let end = segments.map(\.end).max() ?? queryEnd
                let formatter = AppFormatters.mediumDateTime
                healthSleepRangeText = "\(formatter.string(from: start)) -> \(formatter.string(from: end))"

                let sourceNames = Set(segments.map(\.source)).sorted()
                if !sourceNames.isEmpty {
                    healthSleepSourceText = "Source: \(sourceNames.joined(separator: ", "))"
                }

                let derivedKey = sessionRepo.sessionDateString(for: start)
                healthSleepStatusText = derivedKey == sessionDate
                    ? "Matches: Health sleep start maps to session \(derivedKey)."
                    : "Mismatch: Health sleep start maps to \(derivedKey), session is \(sessionDate)."
            } catch {
                healthSleepStatusText = "Apple Health error: \(error.localizedDescription)"
            }
        }
    }

    private func napEventKind(_ eventType: String) -> String? {
        let normalized = eventType
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if normalized == "nap start" || compact == "napstart" { return "start" }
        if normalized == "nap end" || compact == "napend" { return "end" }
        return nil
    }

    private func napLabel(for nap: NapIntervalDisplay) -> String {
        nap.end == nil ? "Nap in progress" : "Nap"
    }

    private func napDetail(for nap: NapIntervalDisplay) -> String {
        let start = nap.start.formatted(date: .omitted, time: .shortened)
        if let end = nap.end {
            let endString = end.formatted(date: .omitted, time: .shortened)
            let duration = nap.durationMinutes.map { TimeIntervalMath.formatMinutes($0) } ?? "-"
            return "\(start) -> \(endString) (\(duration))"
        }
        return "Started at \(start) (no end logged)"
    }
}
