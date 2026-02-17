import SwiftUI

// MARK: - Sleep Plan Summary Card
struct SleepPlanSummaryCard: View {
    let wakeBy: Date
    let recommendedInBed: Date
    let windDown: Date
    let expectedSleepMinutes: Double
    
    private var timeFormatter: DateFormatter { AppFormatters.shortTime }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sleep Plan", systemImage: "bed.double.fill")
                    .font(.headline)
                Spacer()
                Text("Wake by \(timeFormatter.string(from: wakeBy))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended in bed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(timeFormatter.string(from: recommendedInBed))
                        .font(.body.bold())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wind down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(timeFormatter.string(from: windDown))
                        .font(.body.bold())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("If in bed now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSleepDuration(expectedSleepMinutes))
                        .font(.body.bold())
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    /// Format sleep minutes as "Xh Ym" for readability (e.g. 500 min → "8h 20m")
    private func formatSleepDuration(_ minutes: Double) -> String {
        let total = Int(minutes)
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Sleep Plan Override Card
struct SleepPlanOverrideCard: View {
    @Binding var overrideEnabled: Bool
    @Binding var overrideWake: Date
    let onUpdate: (Date) -> Void
    let onClear: () -> Void
    let baselineWake: Date
    
    private var timeFormatter: DateFormatter { AppFormatters.shortTime }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Just for tonight", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $overrideEnabled)
                    .labelsHidden()
                    .onChange(of: overrideEnabled) { newValue in
                        if newValue {
                            onUpdate(overrideWake)
                        } else {
                            onClear()
                        }
                    }
            }
            
            if overrideEnabled {
                DatePicker(
                    "Wake by",
                    selection: $overrideWake,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .onChange(of: overrideWake) { newValue in
                    onUpdate(newValue)
                }
                
                Button(role: .destructive) {
                    overrideWake = baselineWake
                    overrideEnabled = false
                    onClear()
                } label: {
                    Label("Reset to schedule (\(timeFormatter.string(from: baselineWake)))", systemImage: "arrow.uturn.backward")
                }
                .font(.caption)
            } else {
                Text("Uses your Typical Week wake time (\(timeFormatter.string(from: baselineWake)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
    }
}

// MARK: - Pre-Sleep Card
enum PreSleepCardAction: Equatable {
    case start
    case edit(id: String)
}

struct PreSleepCardState: Equatable {
    let logId: String?
    let completionState: String?
    let createdAtUtc: String?
    let localOffsetMinutes: Int?
    
    init(log: StoredPreSleepLog?) {
        logId = log?.id
        completionState = log?.completionState
        createdAtUtc = log?.createdAtUtc
        localOffsetMinutes = log?.localOffsetMinutes
    }
    
    var isLogged: Bool {
        logId != nil
    }
    
    var action: PreSleepCardAction {
        if let logId = logId {
            return .edit(id: logId)
        }
        return .start
    }
}

struct PreSleepCard: View {
    let state: PreSleepCardState
    let onAction: (PreSleepCardAction) -> Void
    
    private var titleText: String {
        if state.isLogged {
            return state.completionState == "skipped" ? "Pre-sleep skipped" : "Pre-sleep logged"
        }
        return "Pre-Sleep Check"
    }
    
    private var subtitleText: String {
        if state.isLogged {
            return "At \(timestamp)"
        }
        return "Quick 30-second check-in"
    }
    
    private var iconName: String {
        if state.isLogged {
            return state.completionState == "skipped" ? "minus.circle.fill" : "checkmark.seal.fill"
        }
        return "moon.stars.fill"
    }
    
    private var iconColor: Color {
        if state.isLogged {
            return state.completionState == "skipped" ? .orange : .green
        }
        return .indigo
    }
    
    private var timestamp: String {
        guard let createdAtUtc = state.createdAtUtc else {
            return "unknown"
        }
        guard let date = AppFormatters.iso8601Fractional.date(from: createdAtUtc) else {
            return "unknown"
        }
        // Use shortTime formatter with custom timezone if needed
        if let offset = state.localOffsetMinutes {
            let f = DateFormatter()
            f.timeStyle = .short
            f.timeZone = TimeZone(secondsFromGMT: offset * 60) ?? .current
            return f.string(from: date)
        } else {
            return AppFormatters.shortTime.string(from: date)
        }
    }
    
    var body: some View {
        Button {
            onAction(state.action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if state.isLogged {
                    Text("Edit")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                        )
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(state.isLogged ? Color(.secondarySystemBackground) : Color.indigo.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                state.isLogged ? Color(.separator) : Color.indigo.opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )
            .foregroundColor(state.isLogged ? .primary : .indigo)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alarm Indicator View
/// Shows scheduled wake alarm time (dose 2 target) when dose 1 has been taken
struct AlarmIndicatorView: View {
    let dose1Time: Date?
    @ObservedObject private var alarmService = AlarmService.shared
    @AppStorage("target_interval_minutes") private var targetIntervalMinutes: Int = 165
    
    var body: some View {
        if let d1 = dose1Time {
            // Use AlarmService's target time if available (accounts for snoozes)
            // Otherwise fall back to calculated time
            let alarmTime = alarmService.targetWakeTime ?? d1.addingTimeInterval(Double(targetIntervalMinutes) * 60)
            let snoozeCount = alarmService.snoozeCount
            
            HStack(spacing: 4) {
                Image(systemName: alarmService.alarmScheduled ? "alarm.fill" : "alarm")
                    .font(.caption)
                    .foregroundColor(alarmService.alarmScheduled ? .orange : .gray)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wake: \(formattedTime(alarmTime))")
                        .font(.caption.bold())
                        .foregroundColor(alarmService.alarmScheduled ? .orange : .gray)
                    
                    if snoozeCount > 0 {
                        Text("(+\(snoozeCount * 10)m)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(alarmService.alarmScheduled ? 0.15 : 0.05))
            .cornerRadius(8)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        AppFormatters.shortTime.string(from: date)
    }
}

// MARK: - Incomplete Session Banner
struct IncompleteSessionBanner: View {
    let sessionDate: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Incomplete Session")
                    .font(.subheadline.bold())
                Text("Complete check-in for \(formattedDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Complete") {
                onComplete()
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.orange))
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var formattedDate: String {
        guard let date = AppFormatters.sessionDate.date(from: sessionDate) else {
            return sessionDate
        }
        return AppFormatters.shortDate.string(from: date)
    }
}
