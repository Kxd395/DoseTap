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
                        Label("Set Weekly Workday Pattern", systemImage: "calendar.badge.clock")
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
                    VStack(spacing: 12) {
                        Toggle("Auto-snooze when appropriate", isOn: $config.autoSnoozeEnabled)
                            .font(.subheadline)

                        Toggle("Override Focus/Do Not Disturb", isOn: $config.focusModeOverride)
                            .font(.subheadline)

                        HStack {
                            Text("Notification Sound")
                                .font(.subheadline)

                            Spacer()

                            Picker("Sound", selection: $config.notificationSound) {
                                Text("Default").tag("default")
                                Text("Gentle").tag("gentle")
                                Text("Urgent").tag("urgent")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
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
                if cloudSyncAvailable {
                    VStack(spacing: 12) {
                        Toggle("Enable iCloud Sync", isOn: $config.icloudSyncEnabled)
                            .font(.subheadline)

                        if config.icloudSyncEnabled {
                            Text("Your logged dose data can sync across your devices using your private iCloud account.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Retention")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Retention Period", selection: $config.dataRetentionDays) {
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("2 years").tag(730)
                        Text("Forever").tag(Int.max)
                    }
                    .pickerStyle(MenuPickerStyle())

                    Text("How long to keep your dose history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                    ? "HealthKit and WHOOP data stay on your device. If you enable iCloud sync, only DoseTap app records sync through your private iCloud account."
                    : "HealthKit and WHOOP data stay on your device. DoseTap does not require an account or transmit health data to third parties.",
                type: .info
            )
        }
    }
}
