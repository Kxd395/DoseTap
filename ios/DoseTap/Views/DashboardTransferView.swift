import SwiftUI
import UIKit
import DoseTapNearby

@MainActor
private final class DashboardPublisherModel: ObservableObject {
    @Published var receipt: String?
    @Published var error: String?
    private weak var service: NearbyReportingSession?
    func attach(_ service: NearbyReportingSession) {
        self.service = service
        service.onSnapshotRequested = { [weak self] context in self?.publish(context: context) }
    }
    private func publish(context: UUID) {
        guard let service, service.state == .paired, service.contextID == context else { return }
        receipt = nil; error = nil
        do {
            let reservation = try DashboardPublisherIdentity().reserve()
            let snapshot = try SessionRepository.shared.dashboardSnapshot(
                sourceID: reservation.sourceID, sequence: reservation.sequence)
            let bytes = try JSONEncoder().encode(snapshot)
            try service.sendSnapshot(bytes, contextID: context)
            receipt = "Report \(reservation.sequence) queued for transfer. Check the iPad for its validation result."
        } catch {
            // Neither a failed write nor unavailable protected storage may reset
            // source identity. Never expose payloads or underlying paths in errors.
            service.stop()
            self.error = "The report could not be prepared or queued. No phone records were changed. Unlock the phone and start a new connection to retry."
        }
    }
}

struct DashboardTransferView: View {
    @StateObject private var service = NearbyReportingSession(role: .publisher)
    @StateObject private var model = DashboardPublisherModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text("Share a read-only report with your nearby iPad. Keep both apps open. The iPad cannot change phone records or alarms.")
                Text("This report contains sensitive health information. Confirm the matching code only on your own iPad. Provider data is not included.")
            }
            Section("Connection") {
                Text(status)
                if service.state == .stopped || service.state == .failed {
                    Button("Start nearby reporting") {
                        model.receipt = nil; model.error = nil; service.start()
                    }.accessibilityIdentifier("dashboard-transfer-start")
                } else {
                    Button("End connection") { service.stop() }
                        .accessibilityIdentifier("dashboard-transfer-stop")
                }
            }
            if let code = service.pairingCode {
                Section("Compare on both devices") {
                    Text(code).font(.system(.largeTitle, design: .monospaced)).bold()
                        .accessibilityIdentifier("dashboard-pairing-code").privacySensitive()
                    Text("Check that these six digits also appear on your iPad. Nothing needs to be copied or typed.")
                    Button("Codes match") { service.confirmMatchingCode() }
                        .disabled(service.codeConfirmed)
                    if service.codeConfirmed { Text("Confirmed here. Confirm on the iPad too.") }
                    Button("Codes do not match", role: .destructive) { service.stop() }
                }
            }
            if let peer = service.invitationPeer {
                Section("Connection request") {
                    Text(peer.displayName)
                    Text("Accept only the iPad you are connecting now. Next, compare the six digits shown on both screens.")
                    Button("Accept this connection") { service.acceptInvitation() }
                        .accessibilityIdentifier("dashboard-invitation-accept")
                    Button("Reject") { service.rejectInvitation() }
                        .accessibilityIdentifier("dashboard-invitation-reject")
                }
            }
            if service.state == .paired {
                Section { Text("Paired. Use Refresh on the iPad to request a report from this phone.") }
            }
            if let receipt = model.receipt { Section("Last transfer attempt") { Text(receipt) } }
            if let message = model.error ?? service.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Nearby dashboard")
        .onAppear { model.attach(service) }
        .onDisappear { service.stop(); service.onSnapshotRequested = nil }
        .onChange(of: scenePhase) { phase in if phase == .background { service.stop() } }
    }
    private var status: String {
        switch service.state {
        case .stopped: return "Not connected"
        case .discovering: return "Waiting for an iPad connection request"
        case .invitation: return "Review the connection request"
        case .connecting: return "Connecting"
        case .authenticating: return "Preparing a secure connection"
        case .verifying: return "Compare the six digits on both devices"
        case .paired: return "Authenticated nearby connection"
        case .failed: return "Connection ended; start again to retry"
        }
    }
}
