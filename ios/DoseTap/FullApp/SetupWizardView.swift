import SwiftUI

struct SetupWizardView: View {
    @StateObject private var setupService = SetupWizardService()
    @Binding var isSetupComplete: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                setupProgressBar
                
                // Content area
                ZStack {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            stepContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                
                // Navigation buttons
                navigationButtons
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            setupService.validateCurrentStep()
        }
        .onChange(of: setupService.userConfig.setupCompleted) { completed in
            if completed {
                isSetupComplete = true
            }
        }
    }
    
    private var setupProgressBar: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(1...5, id: \.self) { step in
                    Circle()
                        .fill(step <= setupService.currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                    
                    if step < 5 {
                        Rectangle()
                            .fill(step < setupService.currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Text("Step \(setupService.currentStep) of 5")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(setupService.currentStep) of 5")
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch setupService.currentStep {
        case 1:
            SleepScheduleStepView(config: $setupService.userConfig.sleepSchedule)
        case 2:
            MedicationStepView(config: $setupService.userConfig.medicationProfile)
        case 3:
            DoseWindowStepView(config: $setupService.userConfig.doseWindow)
        case 4:
            NotificationStepView(
                config: $setupService.userConfig.notifications,
                requestPermissions: setupService.requestNotificationPermissions
            )
        case 5:
            PrivacyStepView(config: $setupService.userConfig.privacy)
        default:
            EmptyView()
        }
    }
    
    private var navigationButtons: some View {
        VStack(spacing: 12) {
            // Validation errors
            if !setupService.validationErrors.isEmpty || !setupService.validationWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review before continuing")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    ForEach(setupService.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityElement(children: .combine)
                    }
                    ForEach(setupService.validationWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal, 20)
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if setupService.canGoBack {
                    Button("Back") {
                        setupService.previousStep()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(setupService.isLoading)
                }
                
                Spacer()
                
                Button(setupService.currentStep == 5 ? "Complete Setup" : "Continue") {
                    setupService.nextStep()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!setupService.canProceed)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
        }
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Preview

struct SetupWizardView_Previews: PreviewProvider {
    static var previews: some View {
        SetupWizardView(isSetupComplete: .constant(false))
    }
}
