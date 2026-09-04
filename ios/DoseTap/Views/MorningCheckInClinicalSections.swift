//
//  MorningCheckInClinicalSections.swift
//  DoseTap
//

import SwiftUI
import DoseCore

struct MorningCheckInNightContextSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Night Context")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Night Type", icon: "calendar.badge.clock") {
                OptionGrid(
                    options: NightType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.nightType)
                )

                Toggle(
                    "This was my first night off after a work block",
                    isOn: $viewModel.firstNightOffAfterWorkBlock
                )
                .padding(.top, 8)
            }

            MorningCheckInSectionCard(title: "How Did You Wake?", icon: "alarm") {
                OptionGrid(
                    options: WakeType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.wakeType)
                )
            }

            MorningCheckInSectionCard(title: "Next-Day Demand", icon: "briefcase") {
                OptionGrid(
                    options: NextDayDemand.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.nextDayDemand)
                )
            }

            MorningCheckInSectionCard(title: "What Woke You For Dose 2?", icon: "moon.stars") {
                OptionGrid(
                    options: Dose2WakeMethod.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.dose2WakeMethod)
                )
            }

            MorningCheckInSectionCard(title: "Back To Sleep After Dose 2", icon: "bed.double") {
                OptionGrid(
                    options: BackToSleepDuration.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.backToSleepDuration)
                )
            }
        }
    }
}

struct MorningCheckInWorkSafetySection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Work / Safety Context")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Work Demand And Safety", icon: "briefcase.fill") {
                Toggle("Add work / safety context", isOn: $viewModel.hasWorkSafetyContext.animation(.spring(response: 0.3)))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))

                if viewModel.hasWorkSafetyContext {
                    Divider()

                    Text("What set your wake requirement?")
                        .font(.subheadline.weight(.semibold))
                    OptionGrid(
                        options: WakeRequirement.allCases,
                        selection: morningCheckInOptionalBinding(viewModel, \.wakeRequirement)
                    )

                    Toggle("Record next shift window", isOn: $viewModel.trackShiftWindow.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .indigo))

                    if viewModel.trackShiftWindow {
                        DatePicker(
                            "Shift start",
                            selection: $viewModel.shiftStartAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "Shift end",
                            selection: $viewModel.shiftEndAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle("Record next required wake time", isOn: $viewModel.trackNextRequiredWake.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .orange))

                    if viewModel.trackNextRequiredWake {
                        DatePicker(
                            "Next required wake",
                            selection: $viewModel.nextRequiredWakeAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Stepper(value: $viewModel.commuteMinutes, in: 0...240, step: 5) {
                        HStack {
                            Text("Commute burden")
                            Spacer()
                            Text("\(viewModel.commuteMinutes) min")
                                .foregroundColor(.secondary)
                        }
                    }

                    MorningCheckInScoreSlider(
                        value: $viewModel.drivingConfidence,
                        range: 1...5,
                        accentColor: .blue,
                        lowLabel: "Not safe",
                        highLabel: "Confident"
                    )

                    MorningCheckInScoreSlider(
                        value: $viewModel.daytimeSleepiness,
                        range: 1...5,
                        accentColor: .purple,
                        lowLabel: "Alert",
                        highLabel: "Very sleepy"
                    )

                    Text("Cataplexy burden")
                        .font(.subheadline.weight(.semibold))
                    OptionGrid(
                        options: CataplexyBurden.allCases,
                        selection: morningCheckInOptionalBinding(viewModel, \.cataplexyBurden)
                    )
                }
            }
        }
    }
}

struct MorningCheckInClinicalContextSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Clinical Reference Context")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Sleep Disorders / Med Context", icon: "cross.case.fill") {
                Toggle("Add clinical reference context", isOn: $viewModel.hasClinicalContext.animation(.spring(response: 0.3)))
                    .toggleStyle(SwitchToggleStyle(tint: .red))

                if viewModel.hasClinicalContext {
                    Divider()

                    Text("Diagnosed or relevant sleep disorders")
                        .font(.subheadline.weight(.semibold))
                    MultiSelectGrid(
                        options: SleepDisorder.allCases,
                        selections: $viewModel.sleepDisorders
                    )

                    TextField(
                        "Sleep disorder notes, severity, treatment status",
                        text: $viewModel.sleepDisorderNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Stimulants, sedating meds, pain meds, CPAP/oral appliance notes",
                        text: $viewModel.coMedicationNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                    Toggle("DNA / pharmacogenomic report suggests faster processing", isOn: $viewModel.pharmacogenomicFastMetabolizer)
                        .toggleStyle(SwitchToggleStyle(tint: .mint))
                    Toggle("Clinician has reviewed this genetic context", isOn: $viewModel.pharmacogenomicClinicianReviewed)
                        .toggleStyle(SwitchToggleStyle(tint: .green))

                    TextField(
                        "Pharmacogenomic notes or report wording",
                        text: $viewModel.pharmacogenomicNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

struct MorningCheckInSymptomTogglesSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Any Issues?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                symptomToggleButton(title: "Physical Pain", icon: "figure.wave", isActive: viewModel.hasPhysicalSymptoms) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.hasPhysicalSymptoms.toggle()
                    }
                }

                symptomToggleButton(title: "Sick/Respiratory", icon: "lungs.fill", isActive: viewModel.hasRespiratorySymptoms) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.hasRespiratorySymptoms.toggle()
                    }
                }
            }
        }
    }

    private func symptomToggleButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isActive ? Color.red.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isActive ? .red : .secondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.red : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct MorningCheckInPhysicalSymptomsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    @Binding var showPainEntryEditor: Bool
    @Binding var editingPainEntry: PreSleepLogAnswers.PainEntry?

    var body: some View {
        VStack(spacing: 16) {
            Text("Physical Symptoms")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Pain detail by area + side", icon: "figure.arms.open") {
                VStack(spacing: 10) {
                    if viewModel.painEntries.isEmpty {
                        Text("Add entries like Mid Back (Both) 2/10 and Lower Back (Right) 9/10.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.painEntries, id: \.entryKey) { entry in
                            HStack(spacing: 10) {
                                GranularPainEntryRow(entry: entry)
                                Spacer(minLength: 4)

                                Button {
                                    editingPainEntry = entry
                                    showPainEntryEditor = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    viewModel.removePainEntry(entry.entryKey)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(10)
                        }
                    }

                    Button {
                        editingPainEntry = nil
                        showPainEntryEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Pain Entry")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(10)
                    }
                }
            }

            MorningCheckInSectionCard(title: "Headache", icon: "brain.head.profile") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Headache", isOn: $viewModel.hasHeadache)
                    if viewModel.hasHeadache {
                        OptionGrid(
                            options: HeadacheSeverity.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.headacheSeverity)
                        )
                        OptionGrid(
                            options: HeadacheLocation.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.headacheLocation)
                        )
                        Toggle("Migraine-like", isOn: $viewModel.isMigraine)
                    }
                }
            }

            MorningCheckInSectionCard(title: "Muscle Stiffness", icon: "figure.strengthtraining.traditional") {
                OptionGrid(
                    options: StiffnessLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.muscleStiffness)
                )
            }

            MorningCheckInSectionCard(title: "Muscle Soreness", icon: "figure.cooldown") {
                OptionGrid(
                    options: SorenessLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.muscleSoreness)
                )
            }

            MorningCheckInSectionCard(title: "Reflux / Heartburn", icon: "flame.fill") {
                OptionGrid(
                    options: SymptomBurden.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.refluxBurden)
                )
            }

            MorningCheckInSectionCard(title: "Restless Legs / Body Restlessness", icon: "figure.walk.motion") {
                OptionGrid(
                    options: SymptomBurden.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.restlessLegsBurden)
                )
            }

            MorningCheckInSectionCard(title: "Bathroom Urgency Overnight", icon: "drop.circle.fill") {
                OptionGrid(
                    options: SymptomBurden.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.bathroomUrgencyBurden)
                )
            }

            MorningCheckInSectionCard(title: "Pain Notes", icon: "note.text") {
                TextField("Add anything specific that stood out", text: $viewModel.painNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
}

struct MorningCheckInRespiratorySymptomsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Nose", icon: "wind") {
                MorningCheckInCongestionPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Throat", icon: "mouth") {
                MorningCheckInThroatPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Cough", icon: "lungs") {
                OptionGrid(
                    options: CoughType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.coughType)
                )
            }

            MorningCheckInSectionCard(title: "Sinus Pressure", icon: "face.dashed") {
                OptionGrid(
                    options: SinusPressureLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.sinusPressure)
                )
            }

            MorningCheckInSectionCard(title: "Illness Severity", icon: "thermometer.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Feeling feverish", isOn: $viewModel.feelingFeverish)
                    OptionGrid(
                        options: SicknessLevel.allCases,
                        selection: morningCheckInOptionalBinding(viewModel, \.sicknessLevel)
                    )
                    TextField("Respiratory notes", text: $viewModel.respiratoryNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
}

struct MorningCheckInSleepEnvironmentSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showSleepEnvironmentSection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "bed.double.circle")
                        .foregroundColor(.teal)
                    Text("Sleep Environment")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepEnvironmentSection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showSleepEnvironmentSection {
                VStack(spacing: 16) {
                    Toggle("Add room/setup details", isOn: $viewModel.hasSleepEnvironment.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .teal))

                    if viewModel.hasSleepEnvironment {
                        MorningCheckInSectionCard(title: "Room Temperature", icon: "thermometer") {
                            OptionGrid(
                                options: PreSleepLogAnswers.RoomTemp.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentRoomTemp)
                            )
                        }

                        MorningCheckInSectionCard(title: "Noise Level", icon: "speaker.wave.2.fill") {
                            OptionGrid(
                                options: PreSleepLogAnswers.NoiseLevel.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentNoiseLevel)
                            )
                        }

                        MorningCheckInSectionCard(title: "Sleep Aids / Setup", icon: "moon.zzz") {
                            OptionGrid(
                                options: PreSleepLogAnswers.SleepAid.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentSleepAid)
                            )
                        }

                        MorningCheckInSectionCard(title: "Environment Notes", icon: "note.text") {
                            TextField("Example: outside noise, too warm, travel setup", text: $viewModel.sleepEnvironmentNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct MorningCheckInSleepTherapySection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showSleepTherapySection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "wind")
                        .foregroundColor(.cyan)
                    Text("Sleep Therapy Device")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepTherapySection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showSleepTherapySection {
                VStack(spacing: 16) {
                    Toggle("Used Sleep Therapy Device", isOn: $viewModel.usedSleepTherapy.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))

                    if viewModel.usedSleepTherapy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Type")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(SleepTherapyDevice.allCases.filter { $0 != .none }, id: \.self) { device in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            viewModel.sleepTherapyDevice = device
                                        }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: device.icon)
                                                .font(.title2)
                                                .foregroundColor(viewModel.sleepTherapyDevice == device ? .cyan : .secondary)
                                            Text(device.rawValue)
                                                .font(.caption)
                                                .foregroundColor(viewModel.sleepTherapyDevice == device ? .primary : .secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.sleepTherapyDevice == device ? Color.cyan.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(viewModel.sleepTherapyDevice == device ? Color.cyan : Color.clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        MorningCheckInSectionCard(title: "How Much Of The Night?", icon: "percent") {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Compliance")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(viewModel.sleepTherapyCompliance)%")
                                        .font(.headline)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.sleepTherapyCompliance) },
                                        set: { viewModel.sleepTherapyCompliance = Int($0.rounded()) }
                                    ),
                                    in: 0...100,
                                    step: 5
                                )
                                .tint(.cyan)
                            }
                        }

                        MorningCheckInSectionCard(title: "Sleep Therapy Notes", icon: "note.text") {
                            TextField("Mask fit, comfort, leaks, or anything notable", text: $viewModel.sleepTherapyNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct MorningCheckInNarcolepsySection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showNarcolepsySection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.indigo)
                    Text("Narcolepsy Symptoms")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showNarcolepsySection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showNarcolepsySection {
                VStack(spacing: 8) {
                    Toggle("Sleep Paralysis", isOn: $viewModel.hadSleepParalysis).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Hallucinations", isOn: $viewModel.hadHallucinations).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Automatic Behavior", isOn: $viewModel.hadAutomaticBehavior).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Fell Out Of Bed", isOn: $viewModel.fellOutOfBed).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Confusion On Waking", isOn: $viewModel.hadConfusionOnWaking).toggleStyle(SwitchToggleStyle(tint: .indigo))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
