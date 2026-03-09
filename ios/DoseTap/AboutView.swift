import SwiftUI

// Extracted from SettingsView.swift — About screen

// MARK: - About View
struct AboutView: View {
    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("DoseTap")
                        .font(.title.bold())

                    Text("XYWAV Dose Timer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Version \(versionString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Section("Core Features") {
                Label("150-240 minute dose window", systemImage: "timer")
                Label("Smart notifications", systemImage: "bell.badge")
                Label("Sleep event tracking", systemImage: "bed.double.fill")
                Label("Health data integration", systemImage: "heart.text.square")
                Label("Offline-first design", systemImage: "wifi.slash")
            }

            Section("Privacy") {
                Label("All data stored locally by default", systemImage: "lock.shield.fill")
                Label("No account required", systemImage: "person.badge.minus")
                Label("DoseTap does not send health data to its own servers", systemImage: "hand.raised.fill")
                Label("HealthKit access is read-only", systemImage: "heart.slash")
            }

            Section("Medical Use") {
                Label("Use DoseTap as a reminder and log, not as a substitute for medical advice", systemImage: "cross.case")
                Label("Always follow your prescriber's instructions for dose timing and safety", systemImage: "stethoscope")
            }

            Section("Help") {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy Policy", systemImage: "doc.text")
                }

                NavigationLink {
                    SupportView()
                } label: {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("About")
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Summary") {
                Text("DoseTap stores your logged dose history and settings on your device.")
                Text("DoseTap reads Apple Health sleep and biometric data only after you grant permission.")
                Text("DoseTap does not write to Apple Health.")
                Text("DoseTap does not require an account.")
            }

            Section("Collected Data") {
                Text("If you enable Apple Health, DoseTap can read sleep analysis, heart rate, respiratory rate, heart rate variability, and resting heart rate.")
                Text("If you enable WHOOP, DoseTap can read WHOOP sleep and recovery data using the account you authorize.")
                Text("If you enable on-device analytics, event logs stay on your device and are used for diagnostics and exports only.")
            }

            Section("Storage") {
                Text("Your dose logs, settings, and exported files are stored locally on-device.")
                Text("Deleting the app removes its local sandbox data.")
                Text("DoseTap does not sell or share health data with advertisers or data brokers.")
            }

            Section("Contact") {
                Text("Support: support@dosetap.app")
            }
        }
        .navigationTitle("Privacy Policy")
    }
}

private struct SupportView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Contact") {
                Button {
                    guard let emailURL = URL(string: "mailto:support@dosetap.app?subject=DoseTap%20Support") else {
                        return
                    }
                    openURL(emailURL)
                } label: {
                    Label("Email support@dosetap.app", systemImage: "envelope")
                }
                .buttonStyle(.plain)

                Text("If Mail is not configured on this device, contact support@dosetap.app from any email client.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Include") {
                Text("Describe what happened, what you expected, and the steps to reproduce it.")
                Text("If requested, export a support bundle from Settings to share diagnostic information.")
            }
        }
        .navigationTitle("Support")
    }
}
