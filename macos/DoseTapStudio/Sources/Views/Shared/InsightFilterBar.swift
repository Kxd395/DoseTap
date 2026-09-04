import SwiftUI

struct InsightFilterBar: View {
    @Binding var filters: InsightFilterState
    var showsSearch = true
    var showsLateDose = false
    var showsSkipped = false
    var showsQualityIssues = true
    var showsTrainable = true
    var showsWorkSafetyContext = true
    var showsClinicalContext = true

    var body: some View {
        HStack(spacing: 12) {
            if showsSearch {
                TextField("Search date, cohort, note, source", text: $filters.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            if showsLateDose {
                Toggle("Late Dose 2", isOn: $filters.lateDoseOnly)
                    .toggleStyle(.switch)
            }

            if showsSkipped {
                Toggle("Skipped", isOn: $filters.skippedOnly)
                    .toggleStyle(.switch)
            }

            if showsQualityIssues {
                Toggle("Quality Issues", isOn: $filters.qualityIssuesOnly)
                    .toggleStyle(.switch)
            }

            if showsTrainable {
                Toggle("Trainable", isOn: $filters.trainableOnly)
                    .toggleStyle(.switch)
            }

            if showsWorkSafetyContext {
                Toggle("Work / Safety", isOn: $filters.workSafetyContextOnly)
                    .toggleStyle(.switch)
            }

            if showsClinicalContext {
                Toggle("Clinical", isOn: $filters.clinicalContextOnly)
                    .toggleStyle(.switch)
            }

            Picker("Night Type", selection: $filters.nightType) {
                ForEach(InsightNightTypeFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            Picker("Wake", selection: $filters.wakeType) {
                ForEach(InsightWakeTypeFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            Picker("Schedule", selection: $filters.schedule) {
                ForEach(InsightScheduleFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            if !filters.isDefault {
                Button("Reset") {
                    filters = InsightFilterState()
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
    }
}
