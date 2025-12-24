import SwiftUI

/// Welcome screen shown when no folder is selected
struct WelcomeView: View {
    @Binding var showingFolderPicker: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("DoseTap Studio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Analytics Companion for DoseTap iOS")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("Import and analyze your DoseTap data:")
                    .font(.headline)
                
                Label("View dose timing and adherence trends", systemImage: "clock.circle")
                Label("Monitor WHOOP health metrics correlation", systemImage: "heart.circle")
                Label("Track inventory and refill schedules", systemImage: "pills.circle")
                Label("Export detailed reports and insights", systemImage: "doc.text.circle")
            }
            .padding(.horizontal, 20)
            
            // Getting started
            VStack(spacing: 16) {
                Text("To get started, select your DoseTap export folder:")
                    .font(.body)
                    .multilineTextAlignment(.center)
                
                Button("Choose Export Folder") {
                    showingFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 20)
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Expected files:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• events.csv - Dose events and user actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• sessions.csv - Complete dose sessions with metrics")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• inventory.csv - Medication inventory snapshots")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: 500)
        .padding(40)
    }
}

#Preview {
    WelcomeView(showingFolderPicker: .constant(false))
}
