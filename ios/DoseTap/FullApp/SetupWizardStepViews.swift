import SwiftUI

struct SleepScheduleStepView: View {
    @Binding var config: SleepScheduleConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Sleep Schedule",
                subtitle: "Help us understand your typical sleep pattern for optimal dose timing"
            )

            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    TimePickerSheetRow(
                        title: "Usual Bedtime",
                        selection: $config.usualBedtime,
                        accessibilityLabel: "Usual bedtime"
                    )
                    TimePickerSheetRow(
                        title: "Usual Wake Time",
                        selection: $config.usualWakeTime,
                        accessibilityLabel: "Usual wake time"
                    )
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("My bedtime varies significantly", isOn: $config.varyBedtime)
                        .font(.subheadline)

                    if config.varyBedtime {
                        Text("We'll provide flexible timing recommendations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                NavigationLink {
                    SleepPlanDetailView()
                } label: {
                    HStack {
                        Label("Set Weekly Schedule", systemImage: "calendar.badge.clock")
                        Spacer()
                        Text("Optional")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            InfoBoxView(
                message: "Your sleep schedule helps determine safe dosing windows. XYWAV should only be taken when you can remain in bed for at least 4 hours.",
                type: .info
            )
        }
    }
}

struct MedicationStepView: View {
    @Binding var config: WizardMedicationConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Medication Profile",
                subtitle: "Configure your XYWAV prescription details for accurate tracking"
            )

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Medication Name")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("XYWAV", text: $config.medicationName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dose 1 (mg)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("450", value: $config.doseMgDose1, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dose 2 (mg)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("225", value: $config.doseMgDose2, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bottle Information")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Doses per bottle")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("60", value: $config.dosesPerBottle, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total mg per bottle")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("9000", value: $config.bottleMgTotal, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)

            InfoBoxView(
                message: "This information helps track your medication supply and maintain accurate records. Always follow your prescriber's instructions. DoseTap does not replace medical advice.",
                type: .info
            )
        }
    }
}

struct DoseWindowStepView: View {
    @Binding var config: DoseWindowConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Dose Timing",
                subtitle: "Customize your dose window preferences within safe medical limits"
            )

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dose 2 Target Interval")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(config.minMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(config.defaultTargetMinutes) min")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("\(config.maxMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(config.defaultTargetMinutes) },
                                set: { config.defaultTargetMinutes = Int($0) }
                            ),
                            in: Double(config.minMinutes)...Double(config.maxMinutes),
                            step: 5
                        )
                        .accentColor(.blue)

                        Text("Time between Dose 1 and Dose 2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Snooze Step")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $config.snoozeStepMinutes) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .accessibilityLabel("Snooze step")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Snoozes")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $config.maxSnoozes) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .accessibilityLabel("Max snoozes")
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            InfoBoxView(
                message: "The 150-240 minute window is medically required for XYWAV safety. Your target time can be adjusted within this range.",
                type: .warning
            )
        }
    }
}

struct NotificationStepView: View {
    @Binding var config: NotificationConfig
    let requestPermissions: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Notifications",
                subtitle: "Configure alerts and reminders for safe medication timing"
            )

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Notifications")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Required for dose reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if config.notificationsAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Permission") {
                                Task {
                                    await requestPermissions()
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                if config.notificationsAuthorized {
                    // Only choices that the app applies are shown here. Auto-snooze and
                    // sound choices were removed because nothing read them (DOSETAP-91).
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Override Focus/Do Not Disturb", isOn: $config.focusModeOverride)
                            .font(.subheadline)

                        Text("Snooze length and count are set in the previous step. Reminder sound uses the iOS notification sound.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notifications are strongly recommended for safety-critical reminders.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Toggle("I understand reminders may not fire without notifications", isOn: $config.acknowledgedNotificationRisk)
                            .font(.caption)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }

            if config.focusModeOverride {
                InfoBoxView(
                    message: "Critical alerts require special permission and are intended for medical safety. This feature requires App Store approval.",
                    type: .warning
                )
            }
        }
    }
}

struct PrivacyStepView: View {
    @Binding var config: PrivacyConfig

    private var cloudSyncAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DoseTapCloudSyncEnabled") as? Bool ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Privacy & Data",
                subtitle: "Control how your health data is stored and shared"
            )

            VStack(spacing: 16) {
                // No automatic age-based deletion exists, so setup does not offer a
                // retention period it cannot enforce (DOSETAP-91).
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Retention")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Your records stay on this device until you delete them in Settings. DoseTap does not delete history automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                VStack(spacing: 12) {
                    Toggle("On-Device Usage Diagnostics", isOn: $config.analyticsEnabled)
                        .font(.subheadline)

                    Text("Keep local diagnostic event logs on this device to help with exports and troubleshooting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            InfoBoxView(
                message: cloudSyncAvailable
                    ? "HealthKit and WHOOP data stay on your device. This build can sync DoseTap records through your private iCloud account when you use the manual sync controls."
                    : "HealthKit and WHOOP data stay on your device. DoseTap does not require an account or transmit health data to third parties.",
                type: .info
            )
        }
    }
}
