import SwiftUI

enum DataResetPresentation {
    static let warningKey = "data_reset_cleanup_warning"
    static let cleanupWarning = "Local records and settings were cleared, but alarm cleanup could not be verified. Check iOS alarms and notifications before relying on them."

    @MainActor
    static func finishCleanup(repository: SessionRepository, generation: UInt,
                              verifyAlarms: () async -> Bool, defaults: UserDefaults) async {
        guard repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        let verified = await verifyAlarms()
        guard !verified, repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        defaults.set(cleanupWarning, forKey: warningKey)
    }
}

struct DataResetWarningView: View {
    let message: String
    let acknowledge: () -> Void
    @ScaledMetric(relativeTo: .body) private var preferredHeight = 240.0

    var body: some View {
        ScrollView {
            content
        }
        .accessibilityIdentifier("reset-cleanup-warning-scroll")
        .frame(height: min(preferredHeight, 320))
        .background(.regularMaterial)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reset Status", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reset-cleanup-warning-message")
            Button("OK, I understand", action: acknowledge)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reset-cleanup-warning-acknowledge")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
