import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
    @State private var copied = false
    var body: some View {
        List {
            Section {
                Text("Share a read-only report with your nearby iPad. Keep both apps open. The iPad cannot change phone records or alarms.")
                Text("This report contains sensitive health information. Enter the pairing code only in your own DoseTap dashboard. Provider data is not included.")
            }
            Section("Connection") {
                Text(status)
                if service.state == .stopped || service.state == .failed {
                    Button("Start nearby reporting") {
                        model.receipt = nil; model.error = nil; copied = false; service.start()
                    }.accessibilityIdentifier("dashboard-transfer-start")
                } else {
                    Button("End connection") { service.stop(); copied = false }
                        .accessibilityIdentifier("dashboard-transfer-stop")
                }
            }
            if let code = service.pairingCode {
                Section("Pairing code") {
                    Text(code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("dashboard-pairing-code")
                    Text("Enter this full code on the iPad. A new connection uses a new code. Device names alone are not proof of identity.")
                    Button(copied ? "Copy code again" : "Copy pairing code") {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: code]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                        copied = true
                    }.accessibilityIdentifier("dashboard-pairing-copy")
                    if copied { Text("Copied on this device for 60 seconds. The code is not shared through Universal Clipboard.").font(.caption) }
                }
            }
            if let peer = service.invitationPeer {
                Section("Connection request") {
                    Text(peer.displayName)
                    Text("Accept only the iPad where you entered this code. Authentication must finish before a report can be requested.")
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
        case .authenticating: return "Checking the pairing code"
        case .paired: return "Authenticated nearby connection"
        case .failed: return "Connection ended; start again to retry"
        }
    }
}
