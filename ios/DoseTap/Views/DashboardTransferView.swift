import SwiftUI
import UIKit
import DoseTapNearby
import DoseCore

@MainActor
final class DashboardPublisherModel: ObservableObject {
    @Published var receipt: String?
    @Published var error: String?
    @Published private(set) var preparing = false
    @Published private(set) var providerReceipt: String?
    private var evidence: DashboardSleepEvidence?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private let healthEnabled: () -> Bool
    private let loadEvidence: () async throws -> DashboardSleepEvidence
    private weak var service: NearbyReportingSession?
    init(healthEnabled: (() -> Bool)? = nil,
         loadEvidence: (() async throws -> DashboardSleepEvidence)? = nil) {
        self.healthEnabled = healthEnabled ?? { UserSettingsManager.shared.healthKitEnabled }
        self.loadEvidence = loadEvidence ?? {
            try await HealthKitService.shared.dashboardSleepEvidence(endingAt: Date(), timeZone: .current)
        }
    }
    func attach(_ service: NearbyReportingSession) {
        self.service = service
        service.onSnapshotRequested = { [weak self] context in self?.publish(context: context) }
    }
    func stop() {
        generation = UUID(); preparation?.cancel(); preparation = nil
        preparing = false; evidence = nil; providerReceipt = nil
        service?.stop()
    }
    func start(includeHealth: Bool) {
        stop(); receipt = nil; error = nil
        guard includeHealth else { service?.start(); return }
        guard healthEnabled() else {
            error = "Apple Health is disabled in DoseTap Settings. Enable it there, or turn off sleep evidence here to share local records only."
            return
        }
        preparing = true
        let expected = generation
        let load = loadEvidence
        preparation = Task { [weak self] in
            do {
                let packet = try await load()
                guard let self, !Task.isCancelled, generation == expected else { return }
                evidence = packet; preparing = false
                providerReceipt = "Prepared \(packet.samples.count) readable sleep samples through \(packet.queryEnd.formatted(date: .abbreviated, time: .shortened)). Start a new connection to refresh Apple Health."
                service?.start()
            } catch {
                guard let self, !Task.isCancelled, generation == expected else { return }
                preparing = false
                self.error = "Apple Health sleep evidence could not be prepared. Check Health access and retry, or turn off sleep evidence to share local records only. Nothing was sent."
            }
        }
    }
    private func publish(context: UUID) {
        guard let service, service.state == .paired, service.contextID == context else { return }
        receipt = nil; error = nil
        do {
            let reservation = try DashboardPublisherIdentity().reserve()
            var snapshot = try SessionRepository.shared.dashboardSnapshot(
                sourceID: reservation.sourceID, sequence: reservation.sequence)
            if let evidence, let index = snapshot.sections.firstIndex(where: { $0.dataset == .appleHealth }) {
                try evidence.validate(capturedAt: snapshot.capturedAt)
                snapshot.sections[index] = try evidence.section()
            }
            let bytes = try JSONEncoder().encode(snapshot)
            guard bytes.count <= NearbyReportingSession.maximumSnapshotBytes else { throw DashboardSnapshotError.invalidPayload }
            try service.sendSnapshot(bytes, contextID: context)
            receipt = "Report \(reservation.sequence) queued for transfer. Check the iPad for its validation result."
        } catch {
            // Neither a failed write nor unavailable protected storage may reset
            // source identity. Never expose payloads or underlying paths in errors.
            stop()
            self.error = "The report could not be prepared or queued. No phone records were changed. Unlock the phone and start a new connection to retry."
        }
    }
}

struct DashboardTransferView: View {
    @StateObject private var service = NearbyReportingSession(role: .publisher)
    @StateObject private var model = DashboardPublisherModel()
    @State private var includeHealth = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text("Share a read-only report with your nearby iPad. Keep both apps open. The iPad cannot change phone records or alarms.")
                Text("This report contains sensitive health information. Confirm the matching code only on your own iPad. WHOOP is not included.")
            }
            Section("Apple Health sleep evidence") {
                Toggle("Include recent Apple Health sleep", isOn: $includeHealth)
                    .accessibilityIdentifier("dashboard-transfer-health")
                Text("Optional for this connection: the previous 30 elapsed days of original sleep stages, times and source/device descriptions. No cloud upload. Empty results do not establish no sleep or permission. Preparation finishes before pairing starts.")
                    .font(.footnote)
                if model.preparing {
                    ProgressView("Preparing sleep evidence…")
                    Button("Cancel preparation") { model.stop() }
                }
                if let providerReceipt = model.providerReceipt { Text(providerReceipt).font(.footnote) }
            }
            Section("Connection") {
                Text(status)
                if service.state == .stopped || service.state == .failed {
                    Button("Start nearby reporting") {
                        model.start(includeHealth: includeHealth)
                    }.accessibilityIdentifier("dashboard-transfer-start").disabled(model.preparing)
                } else {
                    Button("End connection") { model.stop() }
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
                    Button("Codes do not match", role: .destructive) { model.stop() }
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
        .onDisappear { model.stop(); service.onSnapshotRequested = nil }
        .onChange(of: includeHealth) { _ in model.stop() }
        .onChange(of: scenePhase) { phase in if phase == .background { model.stop() } }
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
