import SwiftUI
import DoseCore

/// Detailed view for configuring typical week schedule
struct SleepPlanDetailView: View {
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    
    var body: some View {
        List {
            Section {
                ForEach(1...7, id: \.self) { weekday in
                    TypicalWeekRowInternal(
                        weekday: weekday,
                        entry: sleepPlanStore.schedule.entry(for: weekday)
                    ) { date, enabled in
                        sleepPlanStore.updateEntry(weekday: weekday, wakeTime: date, enabled: enabled)
                    }
                }
            } header: {
                Label("Typical Week Schedule", systemImage: "calendar.badge.clock")
            } footer: {
                Text("Set your typical wake times for each day. These help the Tonight planner suggest optimal dose times based on your schedule.")
                    .font(.caption)
            }
            
            Section {
                Text("The wake time you set for each day feeds into the Sleep Planner and helps calculate optimal bedtimes. Your actual dose window (150-240 minutes) remains unchanged.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Weekly Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Internal copy of TypicalWeekRow for use in this detail view
private struct TypicalWeekRowInternal: View {
    let weekday: Int
    let entry: TypicalWeekEntry
    let onChange: (Date, Bool) -> Void
    
    @State private var showPicker = false
    
    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return formatter.weekdaySymbols[weekday % 7]
    }
    
    private var wakeTime: Date {
        var components = DateComponents()
        components.hour = entry.wakeByHour
        components.minute = entry.wakeByMinute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { entry.enabled },
                set: { enabled in
                    onChange(wakeTime, enabled)
                }
            )) {
                Text(weekdayName)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Button {
                showPicker.toggle()
            } label: {
                Text(wakeTime, style: .time)
                    .foregroundColor(entry.enabled ? .primary : .secondary)
            }
            .disabled(!entry.enabled)
        }
        .sheet(isPresented: $showPicker) {
            NavigationView {
                DatePicker(
                    "Wake Time",
                    selection: Binding(
                        get: { wakeTime },
                        set: { newTime in
                            onChange(newTime, entry.enabled)
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle("\(weekdayName) Wake Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showPicker = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        SleepPlanDetailView()
    }
}
