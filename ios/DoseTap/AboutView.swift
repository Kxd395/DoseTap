import SwiftUI

// Extracted from SettingsView.swift — About screen

// MARK: - About View
struct AboutView: View {
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
                Label("All data stored locally", systemImage: "lock.shield.fill")
                Label("No account required", systemImage: "person.badge.minus")
                Label("No health data transmitted", systemImage: "hand.raised.fill")
            }
            
            Section {
                Link(destination: URL(string: "https://dosetap.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
                
                Link(destination: URL(string: "https://dosetap.com/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("About")
    }
}
