import SwiftUI

struct SystemAlarmSettingsView: View {
    @ObservedObject private var alarms = AlarmService.shared
    @State private var message: String?
    @State private var busy = false
    @State private var confirmTest = false
    var body: some View {
        Form {
            Section("Dose 2 on the Lock Screen") {
                Text(alarms.lockScreenAlarmStatus)
                if alarms.supportsSystemWakeAlarm {
                    Button("Allow alarms / retry Dose 2 alarm") {
                        Task {
                            busy = true
                            await alarms.authorizeSystemWakeAlarm()
                            message = alarms.lastSchedulingError ?? alarms.lockScreenAlarmStatus
                            busy = false
                        }
                    }
                    Text("iOS manages the alarm sound and Lock Screen controls. Stop silences the alarm; open DoseTap to record a dose or use the app's snooze controls.")
                }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            if alarms.supportsSystemWakeAlarm {
                Section("Try before your next night") {
                    Button("Test alarm in 1 minute") { confirmTest = true }
                        .accessibilityIdentifier("testLockedAlarm")
                    Button("Cancel test alarm") {
                        do { try SystemDoseAlarmFactory.makeTestAlarm()?.cancel(); message = "Test alarm cancelled." }
                        catch { message = error.localizedDescription }
                    }
                    Text("This separate test does not record medication or replace your Dose 2 alarm. Lock the phone after scheduling; also test Silent mode and your usual Focus.")
                }
            }
            if let message { Section("Result") { Text(message).accessibilityIdentifier("systemAlarmTestResult") } }
        }
        .disabled(busy)
        .navigationTitle("Locked-phone alarms")
        .confirmationDialog("Sound a test alarm in 1 minute?", isPresented: $confirmTest, titleVisibility: .visible) {
            Button("Schedule test alarm") {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        let fire = Date().addingTimeInterval(60)
                        guard let test = SystemDoseAlarmFactory.makeTestAlarm() else { return }
                        try await test.schedule(at: fire)
                        guard try test.deadline() == fire else { throw SystemDoseAlarmError.verification }
                        message = "Test alarm verified. Lock your phone now; it will sound in about 1 minute."
                    } catch { message = "Test failed: \(error.localizedDescription)" }
                }
            }
        }
    }
}
