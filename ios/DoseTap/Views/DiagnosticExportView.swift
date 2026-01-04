import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// View for exporting session diagnostics
/// Per SSOT v2.14.0: Settings → Support & Diagnostics → Export Last Session
///
/// Exports:
/// - meta.json (session metadata)
/// - events.jsonl (event stream)
/// - errors.jsonl (errors subset)
///
/// All local, no cloud upload.
struct DiagnosticExportView: View {
    @State private var availableSessions: [String] = []
    @State private var selectedSession: String?
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            Section {
                Text("Export diagnostic logs to share with support or review locally. Logs contain session state transitions and timing data. No personal health data is included.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Section("Available Sessions") {
                if availableSessions.isEmpty {
                    Text("No diagnostic logs available")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(availableSessions, id: \.self) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(formatSessionDate(session))
                                        .font(.headline)
                                    Text(session)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedSession == session {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if selectedSession != nil {
                Section {
                    Button {
                        exportSession()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Selected Session")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            
            Section("What's Included") {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(icon: "doc.text", title: "meta.json", description: "Device, app version, timezone")
                    InfoRow(icon: "list.bullet.rectangle", title: "events.jsonl", description: "Phase transitions, dose times")
                    InfoRow(icon: "exclamationmark.triangle", title: "errors.jsonl", description: "Errors and warnings only")
                }
                .padding(.vertical, 4)
            }
            
            Section("Privacy") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Local export only - no cloud upload", systemImage: "lock.shield")
                    Label("No personal health data included", systemImage: "heart.slash")
                    Label("Session timing and state only", systemImage: "clock")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Export Diagnostics")
        .onAppear {
            loadAvailableSessions()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    private func loadAvailableSessions() {
        Task {
            let sessions = await DiagnosticLogger.shared.availableSessions()
            await MainActor.run {
                availableSessions = sessions
                if selectedSession == nil, let first = sessions.first {
                    selectedSession = first
                }
            }
        }
    }
    
    private func exportSession() {
        guard let session = selectedSession else { return }
        
        isExporting = true
        errorMessage = nil
        
        Task {
            if let url = await DiagnosticLogger.shared.exportSession(session) {
                await MainActor.run {
                    exportURL = url
                    showShareSheet = true
                    isExporting = false
                }
            } else {
                await MainActor.run {
                    errorMessage = "Failed to export session. Files may not exist."
                    isExporting = false
                }
            }
        }
    }
    
    private func formatSessionDate(_ sessionId: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: sessionId) else {
            return sessionId
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .full
        return displayFormatter.string(from: date)
    }
}

// MARK: - Supporting Views

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Preview

#if DEBUG
struct DiagnosticExportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DiagnosticExportView()
        }
    }
}
#endif
