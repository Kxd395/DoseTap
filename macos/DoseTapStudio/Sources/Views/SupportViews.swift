import SwiftUI
import Foundation

/// Support bundle export system with progress tracking and privacy-safe data filtering
/// Implements ASCII specifications for diagnostics and support data export

/// Main support and diagnostics view
struct SupportDiagnosticsView: View {
    @StateObject private var exportManager = SupportBundleExportManager()
    @State private var showPrivacyPolicy = false
    @State private var showExportProgress = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                headerSection
                exportSection
                bundleContentsSection
                supportLinksSection
                Spacer()
            }
            .padding()
            .navigationTitle("Support & Diagnostics")
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            privacyPolicyView
        }
        .sheet(isPresented: $showExportProgress) {
            exportProgressView
        }
        .onReceive(exportManager.$isExporting) { isExporting in
            showExportProgress = isExporting
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Support & Diagnostics")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            
            Text("Export diagnostic data to help resolve issues")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var exportSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Support Bundle")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("events.csv, inventory.csv, logs.txt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Export") {
                    exportManager.startExport()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(exportManager.isExporting)
                .accessibilityLabel("Export Support Bundle")
            }
            
            HStack(spacing: 16) {
                Button("View Privacy Policy") {
                    showPrivacyPolicy = true
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.controlColor))
                .cornerRadius(8)
                .accessibilityLabel("View Privacy Policy")
                
                Button("Contact Support") {
                    handleContactSupport()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.controlColor))
                .cornerRadius(8)
                .accessibilityLabel("Contact Support")
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var bundleContentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bundle contents (privacy-safe):")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 8) {
                bundleItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Event timing patterns",
                    description: "(no personal notes)"
                )
                
                bundleItem(
                    icon: "speedometer",
                    title: "App performance data",
                    description: ""
                )
                
                bundleItem(
                    icon: "exclamationmark.triangle",
                    title: "Error logs",
                    description: "(no identifiers)"
                )
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func bundleItem(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("• \(title)")
                    .font(.body)
                
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    private var supportLinksSection: some View {
        VStack(spacing: 12) {
            Text("Need immediate help?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                Link("Visit Support Center", destination: URL(string: "https://dosetap.com/support")!)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.controlColor))
                    .cornerRadius(8)
                
                Link("Community Forum", destination: URL(string: "https://dosetap.com/community")!)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.controlColor))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var privacyPolicyView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Your data privacy is our top priority. Support bundles contain only diagnostic information needed to resolve technical issues.")
                        .font(.body)
                    
                    Text("What's included:")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("• Anonymous timing patterns\n• Technical performance metrics\n• Error logs without personal identifiers")
                        .font(.body)
                    
                    Text("What's NOT included:")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("• Personal notes or comments\n• Identifying information\n• Health data beyond timing\n• Location data")
                        .font(.body)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        showPrivacyPolicy = false
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private var exportProgressView: some View {
        BundleExportProgressView(exportManager: exportManager)
    }
    
    private func handleContactSupport() {
        // In a real app, this would open the default mail client
        print("📧 Would open mailto:support@dosetap.com")
    }
}

/// Bundle export progress view with real-time updates
struct BundleExportProgressView: View {
    @ObservedObject var exportManager: SupportBundleExportManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            progressSection
            statusSection
            
            if exportManager.isCompleted {
                completionSection
            }
        }
        .padding(24)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .frame(width: 500, height: 350)
        .onChange(of: exportManager.isCompleted) { completed in
            if completed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Generating Support Bundle")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            
            Text("Creating privacy-safe diagnostic package")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: exportManager.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 8)
                .scaleEffect(1.0, anchor: .center)
            
            Text("\(Int(exportManager.progress * 100))%")
                .font(.headline)
                .fontWeight(.medium)
                .accessibilityLabel("\(Int(exportManager.progress * 100)) percent complete")
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(exportManager.steps, id: \.name) { step in
                HStack(spacing: 12) {
                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : 
                          step.isActive ? "arrow.right.circle.fill" : "circle")
                        .foregroundColor(step.isCompleted ? .green : 
                                       step.isActive ? .blue : .secondary)
                    
                    Text(step.name)
                        .font(.body)
                        .foregroundColor(step.isActive ? .primary : .secondary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var completionSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            
            Text("Bundle ready for export")
                .font(.headline)
                .fontWeight(.medium)
            
            Text("Size: \(exportManager.bundleSize)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Support bundle export manager with progress tracking
class SupportBundleExportManager: ObservableObject {
    @Published var isExporting = false
    @Published var isCompleted = false
    @Published var progress: Double = 0.0
    @Published var bundleSize = ""
    @Published var steps: [ExportStep] = [
        ExportStep(name: "Anonymizing event data", isActive: false, isCompleted: false),
        ExportStep(name: "Filtering debug logs", isActive: false, isCompleted: false),
        ExportStep(name: "Creating ZIP archive", isActive: false, isCompleted: false),
        ExportStep(name: "Calculating bundle size", isActive: false, isCompleted: false)
    ]
    
    func startExport() {
        guard !isExporting else { return }
        
        isExporting = true
        isCompleted = false
        progress = 0.0
        resetSteps()
        
        // Simulate export process
        performExportSteps()
    }
    
    private func resetSteps() {
        for i in steps.indices {
            steps[i].isActive = false
            steps[i].isCompleted = false
        }
    }
    
    private func performExportSteps() {
        let stepDuration: TimeInterval = 1.5
        let totalSteps = steps.count
        
        for (index, _) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDuration) {
                // Start current step
                if index < self.steps.count {
                    self.steps[index].isActive = true
                    self.progress = Double(index) / Double(totalSteps)
                }
                
                // Complete current step after half duration
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * 0.5) {
                    if index < self.steps.count {
                        self.steps[index].isActive = false
                        self.steps[index].isCompleted = true
                        self.progress = Double(index + 1) / Double(totalSteps)
                        
                        // Complete export process
                        if index == totalSteps - 1 {
                            self.completeExport()
                        }
                    }
                }
            }
        }
    }
    
    private func completeExport() {
        bundleSize = "2.3 MB"
        isCompleted = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isExporting = false
            self.presentSaveDialog()
        }
    }
    
    private func presentSaveDialog() {
        // In a real app, this would present a save dialog
        // For now, just simulate saving to desktop
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileName = "DoseTap-Support-Bundle-\(Date().formatted(.iso8601.year().month().day())).zip"
        let fileURL = desktopURL.appendingPathComponent(fileName)
        saveBundleToFile(url: fileURL)
    }
    
    private func saveBundleToFile(url: URL) {
        // Create sample support bundle content
        let bundleContent = """
        DoseTap Support Bundle
        Generated: \(Date())
        
        === Event Timing Patterns ===
        (Anonymized timing data would go here)
        
        === Performance Metrics ===
        (App performance data would go here)
        
        === Error Logs ===
        (Filtered error logs would go here)
        """
        
        do {
            try bundleContent.write(to: url, atomically: true, encoding: .utf8)
            print("📦 Support bundle saved to: \(url.path)")
        } catch {
            print("❌ Failed to save support bundle: \(error)")
        }
    }
}

/// Export step data model
struct ExportStep {
    let name: String
    var isActive: Bool
    var isCompleted: Bool
}

#Preview("Support Diagnostics") {
    SupportDiagnosticsView()
}

#Preview("Export Progress") {
    BundleExportProgressView(exportManager: SupportBundleExportManager())
        .padding()
        .background(Color(.windowBackgroundColor))
}
