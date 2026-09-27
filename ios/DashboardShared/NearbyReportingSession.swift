import Foundation
import Combine
@preconcurrency import MultipeerConnectivity

// Bounds queued delegate Data before it crosses to the main actor. Old-session
// releases cannot subtract from a new generation. One overflow queues one abort.
final class NearbyInboundBudget: @unchecked Sendable {
    enum Admission: Equatable { case accepted, reject, ignore }
    private let lock = NSLock()
    private var sessionID: ObjectIdentifier?
    private var authenticated = false, blocked = false
    private var bytes = 0, packets = 0
    func configure(_ session: MCSession?) {
        lock.lock(); defer { lock.unlock() }
        sessionID = session.map(ObjectIdentifier.init)
        authenticated = false; blocked = false; bytes = 0; packets = 0
    }
    func authenticate() { lock.lock(); authenticated = true; lock.unlock() }
    func reserve(_ count: Int, session id: ObjectIdentifier) -> Admission {
        lock.lock(); defer { lock.unlock() }
        guard sessionID == id, !blocked else { return .ignore }
        let packetLimit = authenticated ? NearbyReportingCodec.maximumWireBytes : 128
        let queueLimit = authenticated ? 2 : 4
        guard count <= packetLimit, packets < queueLimit, bytes <= packetLimit * queueLimit - count else {
            blocked = true; return .reject
        }
        bytes += count; packets += 1; return .accepted
    }
    func release(_ count: Int, session id: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        guard sessionID == id else { return }
        bytes -= count; packets -= 1
    }
}

/// Foreground, one-peer reporting only. Names and discovery are untrusted.
/// Requires a fresh publisher code exchanged through a trusted local channel.
/// Clinical payloads are opaque; the receiver must separately validate/cache them.
@MainActor
public final class NearbyReportingSession: NSObject, ObservableObject {
    public typealias Role = NearbyReportingCodec.Role
    public enum State { case stopped, discovering, invitation, connecting, authenticating, paired, failed }
    public enum Failure: Error { case invalidState }
    public nonisolated static let maximumSnapshotBytes = NearbyReportingCodec.maximumSnapshotBytes
    private static let serviceType = "dt-report"
    public let role: Role
    @Published public private(set) var state: State = .stopped
    @Published public private(set) var discoveredPeers: [MCPeerID] = []
    @Published public private(set) var invitationPeer: MCPeerID?
    @Published public private(set) var pairingCode: String?
    @Published public private(set) var errorMessage: String?
    public private(set) var contextID = UUID()
    public var onSnapshot: ((Data, UUID) -> Void)?
    public var onSnapshotRequested: ((UUID) -> Void)?
    public var onDisconnected: (() -> Void)?
    private nonisolated let inboundBudget = NearbyInboundBudget()
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitation: ((Bool, MCSession?) -> Void)?
    private var peer: MCPeerID?
    private var codec: NearbyReportingCodec?
    private var timeout: Task<Void, Never>?
    public init(role: Role) { self.role = role; super.init() }

    public func start() {
        stop()
        let identity = MCPeerID(displayName: role == .publisher ? "DoseTap Phone" : "DoseTap Dashboard")
        let next = MCSession(peer: identity, securityIdentity: nil, encryptionPreference: .required)
        session = next; inboundBudget.configure(next); next.delegate = self; state = .discovering
        if role == .publisher {
            let key = NearbyReportingCodec.randomBytes()
            do { codec = try NearbyReportingCodec(role: role, key: key) } catch { abort(); return }
            pairingCode = NearbyReportingCodec.code(for: key)
            let service = MCNearbyServiceAdvertiser(peer: identity, discoveryInfo: nil, serviceType: Self.serviceType)
            advertiser = service; service.delegate = self; service.startAdvertisingPeer()
        } else {
            let service = MCNearbyServiceBrowser(peer: identity, serviceType: Self.serviceType)
            browser = service; service.delegate = self; service.startBrowsingForPeers()
        }
    }
    public func stop() {
        contextID = UUID(); timeout?.cancel(); timeout = nil
        invitation?(false, nil); invitation = nil; invitationPeer = nil
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        advertiser?.delegate = nil; browser?.delegate = nil; advertiser = nil; browser = nil
        let old = session; session = nil; inboundBudget.configure(nil); old?.delegate = nil; old?.disconnect()
        peer = nil; codec?.invalidate(); codec = nil; pairingCode = nil
        discoveredPeers = []; state = .stopped; errorMessage = nil; onDisconnected?()
    }
    public func connect(to candidate: MCPeerID, pairingCode code: String) throws {
        guard role == .reader, state == .discovering, let session, discoveredPeers.contains(candidate) else { throw Failure.invalidState }
        let key = try NearbyReportingCodec.key(from: code)
        codec = try NearbyReportingCodec(role: role, key: key)
        peer = candidate; state = .connecting
        browser?.invitePeer(candidate, to: session, withContext: nil, timeout: 30)
        browser?.stopBrowsingForPeers(); armTimeout()
    }
    public func acceptInvitation() {
        guard role == .publisher, state == .invitation, let candidate = invitationPeer,
              let handler = invitation, let session else { return }
        invitation = nil; invitationPeer = nil; peer = candidate; state = .connecting
        advertiser?.stopAdvertisingPeer(); armTimeout(); handler(true, session)
    }
    public func rejectInvitation() {
        guard state == .invitation else { return }
        invitation?(false, nil); invitation = nil; invitationPeer = nil
        timeout?.cancel(); timeout = nil; state = .discovering
    }
    public func requestSnapshot() throws {
        guard role == .reader, state == .paired, let packet = try codec?.requestSnapshot() else { throw Failure.invalidState }
        do { try send(packet); armTimeout(request: true) } catch { abort(); throw error }
    }
    /// Fences a delayed producer result against a disconnected/replaced peer.
    public func sendSnapshot(_ bytes: Data, contextID expected: UUID) throws {
        guard expected == contextID, role == .publisher, state == .paired,
              let packet = try codec?.sendSnapshot(bytes) else { throw Failure.invalidState }
        do { try send(packet); timeout?.cancel(); timeout = nil } catch { abort(); throw error }
    }
    private func send(_ bytes: Data) throws {
        guard bytes.count <= NearbyReportingCodec.maximumWireBytes, let peer, let session,
              session.connectedPeers == [peer] else { throw Failure.invalidState }
        try session.send(bytes, toPeers: [peer], with: .reliable)
    }
    private func receive(_ data: Data, from sender: MCPeerID) {
        do {
            guard sender == peer, let result = try codec?.receive(data) else { throw Failure.invalidState }
            for packet in result.outbound { try send(packet) }
            switch result.event {
            case .authenticated:
                state = .paired; inboundBudget.authenticate(); pairingCode = nil; timeout?.cancel(); timeout = nil
            case .requestSnapshot: armTimeout(request: true); onSnapshotRequested?(contextID)
            case .snapshot(let bytes): timeout?.cancel(); timeout = nil; onSnapshot?(bytes, contextID)
            case nil: break
            }
        } catch { abort() }
    }
    private func armTimeout(request: Bool = false) {
        let generation = contextID; timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.contextID == generation, request || self.state != .paired else { return }
            self.abort()
        }
    }
    private func abort() { stop(); state = .failed; errorMessage = "Nearby connection ended. Start again with a new pairing code." }
}

extension NearbyReportingSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard self.session === session else { return }
            guard peerID == self.peer else { self.abort(); return }
            switch state {
            case .connected:
                guard self.state == .connecting else { self.abort(); return }
                self.state = .authenticating
                do {
                    guard let hello = try self.codec?.begin() else { throw Failure.invalidState }
                    try self.send(hello)
                } catch { self.abort() }
            case .notConnected: self.stop()
            case .connecting: break
            @unknown default: self.abort()
            }
        }
    }
    nonisolated public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let identity = ObjectIdentifier(session)
        switch inboundBudget.reserve(data.count, session: identity) {
        case .ignore: return
        case .reject:
            DispatchQueue.main.async { if self.session === session { self.abort() } }
        case .accepted:
            DispatchQueue.main.async {
                defer { self.inboundBudget.release(data.count, session: identity) }
                guard self.session === session else { return }
                self.receive(data, from: peerID)
            }
        }
    }
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                               withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.advertiser === advertiser, self.role == .publisher, self.state == .discovering,
                  self.peer == nil, self.invitation == nil, context == nil else { invitationHandler(false, nil); return }
            self.invitation = invitationHandler; self.invitationPeer = peerID; self.state = .invitation
            self.armTimeout()
        }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard self.browser === browser, self.state == .discovering,
                  !self.discoveredPeers.contains(peerID), self.discoveredPeers.count < 20 else { return }
            self.discoveredPeers.append(peerID)
        }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { if self.browser === browser { self.discoveredPeers.removeAll { $0 == peerID } } }
    }
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { if self.advertiser === advertiser { self.abort() } }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { if self.browser === browser { self.abort() } }
    }
    nonisolated public func session(_ session: MCSession, didReceive stream: InputStream, withName name: String, fromPeer peerID: MCPeerID) {
        stream.close(); DispatchQueue.main.async { if self.session === session { self.abort() } }
    }
    nonisolated public func session(_ session: MCSession, didStartReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel(); DispatchQueue.main.async { if self.session === session { self.abort() } }
    }
    nonisolated public func session(_ session: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        DispatchQueue.main.async { if self.session === session { self.abort() } }
    }
}
