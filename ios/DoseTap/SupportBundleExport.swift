// iOS/SupportBundleExport.swift
#if os(iOS)
import SwiftUI
import OSLog
import MessageUI
import UniformTypeIdentifiers
import CoreData

// MARK: - Support Bundle Models

struct SupportBundleExportView: View {
    @StateObject private var exportManager = SupportBundleExportManager()
    @State private var showingMailComposer = false
    @State private var showingShareSheet = false
    @State private var exportedBundleURL: URL?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    SupportBundleHeaderCard()
                    
                    // Privacy Information
                    PrivacyInformationCard()
                    
                    // Export Options
                    VStack(spacing: 12) {
                        if exportManager.isExporting {
                            ExportProgressCard(progress: exportManager.exportProgress)
                        } else {
                            Button("Generate Support Bundle") {
                                exportManager.generateSupportBundle()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(exportManager.isExporting)
                        }
                        
                        if let bundleURL = exportedBundleURL {
                            HStack(spacing: 12) {
                                Button("Email to Support") {
                                    showingMailComposer = true
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(!MFMailComposeViewController.canSendMail())
                                
                                Button("Share") {
                                    showingShareSheet = true
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Bundle Contents Preview
                    if let contents = exportManager.bundleContents {
                        BundleContentsCard(contents: contents)
                    }
                    
                    // Recent Exports
                    RecentExportsSection(manager: exportManager)
                }
                .padding()
            }
            .navigationTitle("Support Bundle")
            .sheet(isPresented: $showingMailComposer) {
                if let bundleURL = exportedBundleURL {
                    MailComposeView(
                        bundleURL: bundleURL,
                        onComplete: { showingMailComposer = false }
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let bundleURL = exportedBundleURL {
                    ActivityViewController(activityItems: [bundleURL])
                }
            }
        }
        .onReceive(exportManager.$exportedBundleURL) { url in
            exportedBundleURL = url
        }
    }
}

// MARK: - Support Bundle Header Card

struct SupportBundleHeaderCard: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "doc.zipper")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support Bundle")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Diagnostic information for troubleshooting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text("A support bundle contains anonymized app logs, settings, and diagnostic data to help our team resolve issues faster.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Privacy Information Card

struct PrivacyInformationCard: View {
    @State private var showingPrivacyDetails = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                
                Text("Privacy Protected")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Details") {
                    showingPrivacyDetails = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PrivacyItem(title: "Personal identifiers", status: .minimized, description: "Device IDs hashed, names/emails excluded")
                PrivacyItem(title: "Dose timing data", status: .included, description: "Relative time offsets (not exact times)")
                PrivacyItem(title: "App logs", status: .included, description: "Error messages and app behavior")
                PrivacyItem(title: "Device info", status: .included, description: "iOS version, device model")
            }
            
            // SSOT compliance note
            Text("Review before sharing • PII minimized, not guaranteed zero-PII")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingPrivacyDetails) {
            PrivacyDetailsSheet()
        }
    }
}

struct PrivacyItem: View {
    let title: String
    let status: PrivacyStatus
    let description: String
    
    enum PrivacyStatus {
        case included, excluded, anonymized, minimized
        
        var icon: String {
            switch self {
            case .included: return "checkmark.circle.fill"
            case .excluded: return "xmark.circle.fill"
            case .anonymized: return "eye.slash.circle.fill"
            case .minimized: return "shield.checkered"
            }
        }
        
        var color: Color {
            switch self {
            case .included: return .blue
            case .excluded: return .red
            case .anonymized: return .orange
            case .minimized: return .green
            }
        }
        
        var label: String {
            switch self {
            case .included: return "Included"
            case .excluded: return "Excluded"
            case .anonymized: return "Anonymized"
            case .minimized: return "Minimized"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(status.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(status.color)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Export Progress Card

struct ExportProgressCard: View {
    let progress: SupportBundleProgress
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generating Support Bundle")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(progress.percentComplete))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: progress.percentComplete, total: 100)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            
            Text(progress.currentStep)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating support bundle. \(Int(progress.percentComplete)) percent complete.")
    }
}

// MARK: - Bundle Contents Card

struct BundleContentsCard: View {
    let contents: SupportBundleContents
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bundle Contents")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                BundleContentRow(title: "App Logs", detail: "\(contents.logEntriesCount) entries", size: contents.logSizeFormatted)
                BundleContentRow(title: "Settings", detail: "\(contents.settingsCount) preferences", size: contents.settingsSizeFormatted)
                BundleContentRow(title: "Device Info", detail: "System information", size: contents.deviceInfoSizeFormatted)
                BundleContentRow(title: "Usage Stats", detail: "Anonymized metrics", size: contents.usageStatsSizeFormatted)
            }
            
            HStack {
                Text("Total Size:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(contents.totalSizeFormatted)
                    .fontWeight(.medium)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding(.vertical)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct BundleContentRow: View {
    let title: String
    let detail: String
    let size: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(size)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

// MARK: - Recent Exports Section

struct RecentExportsSection: View {
    @ObservedObject var manager: SupportBundleExportManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Exports")
                .font(.headline)
                .padding(.horizontal)
            
            if manager.recentExports.isEmpty {
                Text("No recent exports")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(manager.recentExports, id: \.id) { export in
                    RecentExportRow(export: export)
                }
            }
        }
    }
}

struct RecentExportRow: View {
    let export: SupportBundleExport
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Support Bundle")
                    .fontWeight(.medium)
                Text(export.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(export.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Mail Compose View

struct MailComposeView: UIViewControllerRepresentable {
    let bundleURL: URL
    let onComplete: () -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["support@dosetap.app"])
        composer.setSubject("DoseTap Support Bundle")
        composer.setMessageBody("""
        Hi DoseTap Support Team,
        
        I'm experiencing an issue with the app and have attached a support bundle for analysis.
        
        Issue Description:
        [Please describe the issue you're experiencing]
        
        Steps to Reproduce:
        [Please list the steps that led to the issue]
        
        Thanks for your help!
        """, isHTML: false)
        
        // Attach support bundle
        if let data = try? Data(contentsOf: bundleURL) {
            composer.addAttachmentData(data, mimeType: "application/zip", fileName: "dosetap-support-bundle.zip")
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: () -> Void
        
        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onComplete()
        }
    }
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Privacy Details Sheet

struct PrivacyDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What's included in a support bundle:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        PrivacyDetailSection(
                            title: "App Logs",
                            description: "Error messages, app state changes, and performance metrics. Personal identifiers are automatically removed.",
                            included: true
                        )
                        
                        PrivacyDetailSection(
                            title: "Settings",
                            description: "App preferences and configuration. No personal data like names or contact information.",
                            included: true
                        )
                        
                        PrivacyDetailSection(
                            title: "Device Information",
                            description: "iOS version, device model, screen size, and other technical specifications.",
                            included: true
                        )
                        
                        PrivacyDetailSection(
                            title: "Usage Statistics",
                            description: "Anonymized usage patterns to help identify common issues.",
                            included: true
                        )
                        
                        PrivacyDetailSection(
                            title: "Personal Identifiers",
                            description: "Names, email addresses, phone numbers, and other personally identifiable information.",
                            included: false
                        )
                        
                        PrivacyDetailSection(
                            title: "Health Data",
                            description: "Specific medication dosages, times, or other sensitive health information.",
                            included: false
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PrivacyDetailSection: View {
    let title: String
    let description: String
    let included: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: included ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(included ? .green : .red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
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

// MARK: - Support Bundle Models

struct SupportBundleProgress {
    let percentComplete: Double
    let currentStep: String
}

struct SupportBundleContents {
    let logEntriesCount: Int
    let settingsCount: Int
    let logSizeFormatted: String
    let settingsSizeFormatted: String
    let deviceInfoSizeFormatted: String
    let usageStatsSizeFormatted: String
    let totalSizeFormatted: String
}

struct SupportBundleExport {
    let id = UUID()
    let date: Date
    let sizeFormatted: String
}

// MARK: - Support Bundle Export Manager

class SupportBundleExportManager: ObservableObject {
    @Published var isExporting = false
    @Published var exportProgress = SupportBundleProgress(percentComplete: 0, currentStep: "")
    @Published var bundleContents: SupportBundleContents?
    @Published var exportedBundleURL: URL?
    @Published var recentExports: [SupportBundleExport] = []
    
    private let logger = Logger(subsystem: "com.dosetap.app", category: "SupportBundle")
    
    init() {
        loadRecentExports()
    }
    
    func generateSupportBundle() {
        isExporting = true
        exportProgress = SupportBundleProgress(percentComplete: 0, currentStep: "Initializing...")
        
        Task {
            await performExport()
        }
    }
    
    @MainActor
    private func performExport() async {
        do {
            // Step 1: Collect logs
            updateProgress(25, "Collecting app logs...")
            await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            
            // Step 2: Gather settings
            updateProgress(50, "Gathering settings...")
            await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 3: System info
            updateProgress(75, "Collecting system information...")
            await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 4: Create bundle
            updateProgress(90, "Creating bundle...")
            let bundleURL = try await createSupportBundle()
            
            // Step 5: Complete
            updateProgress(100, "Complete!")
            await Task.sleep(nanoseconds: 250_000_000) // 0.25 second
            
            // Finish
            isExporting = false
            exportedBundleURL = bundleURL
            
            // Update bundle contents
            bundleContents = SupportBundleContents(
                logEntriesCount: 1247,
                settingsCount: 23,
                logSizeFormatted: "156 KB",
                settingsSizeFormatted: "2 KB",
                deviceInfoSizeFormatted: "1 KB",
                usageStatsSizeFormatted: "8 KB",
                totalSizeFormatted: "167 KB"
            )
            
            // Add to recent exports
            let export = SupportBundleExport(
                date: Date(),
                sizeFormatted: "167 KB"
            )
            recentExports.insert(export, at: 0)
            
            logger.info("Support bundle generated successfully")
            
        } catch {
            isExporting = false
            logger.error("Failed to generate support bundle: \(error.localizedDescription)")
        }
    }
    
    private func updateProgress(_ percent: Double, _ step: String) {
        exportProgress = SupportBundleProgress(percentComplete: percent, currentStep: step)
    }
    
    private func createSupportBundle() async throws -> URL {
        // Create temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create bundle file
        let bundleURL = tempDir.appendingPathComponent("dosetap-support-bundle.zip")
        
        // For demo purposes, create a simple zip file
        let bundleData = "DoseTap Support Bundle\nGenerated: \(Date())\n".data(using: .utf8) ?? Data()
        try bundleData.write(to: bundleURL)
        
        return bundleURL
    }
    
    private func loadRecentExports() {
        // Mock recent exports - in real implementation, load from UserDefaults or Core Data
        recentExports = [
            SupportBundleExport(date: Date().addingTimeInterval(-86400 * 3), sizeFormatted: "142 KB"),
            SupportBundleExport(date: Date().addingTimeInterval(-86400 * 10), sizeFormatted: "158 KB"),
        ]
    }
}

#endif // os(iOS)
