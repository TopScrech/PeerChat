import Foundation
@preconcurrency import Network
import Security

@MainActor
final class PeerNetworkSession {
    private enum FrameType: UInt8 {
        case handshake, payload
    }

    private final class ConnectionContext: @unchecked Sendable {
        let connection: NWConnection
        let isOutgoing: Bool
        let expectedPeer: PeerID?
        var peer: PeerID?

        init(connection: NWConnection, isOutgoing: Bool, expectedPeer: PeerID?) {
            self.connection = connection
            self.isOutgoing = isOutgoing
            self.expectedPeer = expectedPeer
        }
    }

    private static let tcpServiceType = "_peerchat._tcp"
    private static let udpServiceType = "_peerchat._udp"
    private static let maximumFrameSize = 12 * 1024 * 1024
    private static let frameHeaderSize = MemoryLayout<UInt32>.size

    weak var delegate: PeerNetworkSessionDelegate?
    let datagramSender: PeerDatagramSender

    private let localPeer: PeerID
    private let status: String
    private let queue = DispatchQueue.main
    private let identity: sec_identity_t
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private var tcpListener: NWListener?
    private var udpListener: NWListener?
    private var tcpBrowser: NWBrowser?
    private var udpBrowser: NWBrowser?
    private var connections: [UUID: ConnectionContext] = [:]
    private var pendingConnections: [ObjectIdentifier: ConnectionContext] = [:]
    private var discoveredTCPPeers: [UUID: (peer: PeerID, endpoint: NWEndpoint)] = [:]
    private var udpConnections: [UUID: NWConnection] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    private var blockedPeers: Set<UUID> = []
    private var isRunning = false

    init(localPeer: PeerID, status: String) {
        guard let identity = PeerTLSIdentity.make() else {
            fatalError("Unable to create the local networking identity")
        }

        self.localPeer = localPeer
        self.status = status
        self.identity = identity
        datagramSender = PeerDatagramSender(localPeerID: localPeer.id)
    }

    func start() {
        guard isRunning == false else {
            return
        }

        isRunning = true
        blockedPeers.removeAll()

        do {
            let tcpListener = try NWListener(using: makeTCPParameters())
            let udpListener = try NWListener(using: makeUDPParameters())
            configure(tcpListener, serviceType: Self.tcpServiceType)
            configure(udpListener, serviceType: Self.udpServiceType)
            self.tcpListener = tcpListener
            self.udpListener = udpListener
            startTCPListener(tcpListener)
            startUDPListener(udpListener)
            startBrowsers()
        } catch {
            print("Network listener setup failed:", error.localizedDescription)
            stop()
        }
    }

    func stop() {
        isRunning = false
        tcpBrowser?.cancel()
        udpBrowser?.cancel()
        tcpListener?.cancel()
        udpListener?.cancel()
        tcpBrowser = nil
        udpBrowser = nil
        tcpListener = nil
        udpListener = nil

        for task in reconnectTasks.values {
            task.cancel()
        }

        reconnectTasks.removeAll()

        for context in pendingConnections.values {
            context.connection.cancel()
        }

        for context in connections.values {
            context.connection.cancel()
        }

        for connection in udpConnections.values {
            connection.cancel()
        }

        pendingConnections.removeAll()
        connections.removeAll()
        discoveredTCPPeers.removeAll()
        udpConnections.removeAll()
        datagramSender.removeAllConnections()
    }

    func restart() {
        stop()
        start()
    }

    func disconnect(_ peer: PeerID) {
        blockedPeers.insert(peer.id)
        reconnectTasks[peer.id]?.cancel()
        reconnectTasks[peer.id] = nil

        if let context = connections.removeValue(forKey: peer.id) {
            context.connection.cancel()
        }

        if let connection = udpConnections.removeValue(forKey: peer.id) {
            connection.cancel()
        }

        datagramSender.setConnection(nil, for: peer.id)
        delegate?.peerNetworkSessionDidDisconnect(peer)
    }

    func isConnected(to peer: PeerID) -> Bool {
        connections[peer.id] != nil
    }

    func send(_ data: Data, to peers: [PeerID], delivery: PeerNetworkDelivery) {
        switch delivery {
        case .reliable:
            guard let frame = makeFrame(type: .payload, body: data) else {
                return
            }

            for peer in peers {
                guard let connection = connections[peer.id]?.connection else {
                    continue
                }

                connection.send(
                    content: frame,
                    completion: .contentProcessed { error in
                        if let error {
                            print("Reliable send failed:", error)
                        }
                    }
                )
            }

        case .bestEffort:
            for peer in peers {
                datagramSender.send(data, to: peer.id)
            }
        }
    }

    private func configure(_ listener: NWListener, serviceType: String) {
        var txtRecord = NWTXTRecord()
        txtRecord["peerID"] = localPeer.id.uuidString
        txtRecord["name"] = localPeer.displayName
        txtRecord["status"] = status
        listener.service = NWListener.Service(
            name: localPeer.displayName,
            type: serviceType,
            txtRecord: txtRecord
        )
        listener.serviceRegistrationUpdateHandler = { change in
            if case .add(let endpoint) = change {
                print("Registered PeerChat service:", endpoint)
            }
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .waiting(let error), .failed(let error):
                print("PeerChat listener state:", error)
            default:
                break
            }
        }
    }

    private func startTCPListener(_ listener: NWListener) {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.startReliableConnection(
                    connection,
                    isOutgoing: false,
                    expectedPeer: nil
                )
            }
        }
        listener.start(queue: queue)
    }

    private func startUDPListener(_ listener: NWListener) {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.startIncomingDatagramConnection(connection)
            }
        }
        listener.start(queue: queue)
    }

    private func startBrowsers() {
        let tcpBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.tcpServiceType, domain: nil),
            using: makeTCPParameters()
        )
        let udpBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.udpServiceType, domain: nil),
            using: makeUDPParameters()
        )
        self.tcpBrowser = tcpBrowser
        self.udpBrowser = udpBrowser

        tcpBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.updateTCPResults(results)
            }
        }
        udpBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.updateUDPResults(results)
            }
        }
        tcpBrowser.stateUpdateHandler = Self.browserStateHandler(name: "TCP")
        udpBrowser.stateUpdateHandler = Self.browserStateHandler(name: "UDP")
        tcpBrowser.start(queue: queue)
        udpBrowser.start(queue: queue)
    }

    nonisolated private static func browserStateHandler(
        name: String
    ) -> @Sendable (NWBrowser.State) -> Void {
        { state in
            switch state {
            case .waiting(let error), .failed(let error):
                print("PeerChat \(name) browser state:", error)
            default:
                break
            }
        }
    }

    private func updateTCPResults(_ results: Set<NWBrowser.Result>) {
        let peers = discoveredPeers(in: results)
        let removedIDs = Set(discoveredTCPPeers.keys).subtracting(peers.keys)

        for peerID in removedIDs {
            reconnectTasks[peerID]?.cancel()
            reconnectTasks[peerID] = nil
        }

        discoveredTCPPeers = peers

        for discovered in peers.values {
            connectIfNeeded(to: discovered.peer, endpoint: discovered.endpoint)
        }
    }

    private func updateUDPResults(_ results: Set<NWBrowser.Result>) {
        let peers = discoveredPeers(in: results)
        let removedIDs = Set(udpConnections.keys).subtracting(peers.keys)

        for peerID in removedIDs {
            udpConnections.removeValue(forKey: peerID)?.cancel()
            datagramSender.setConnection(nil, for: peerID)
        }

        for discovered in peers.values where blockedPeers.contains(discovered.peer.id) == false {
            guard udpConnections[discovered.peer.id] == nil else {
                continue
            }

            startOutgoingDatagramConnection(
                to: discovered.peer,
                endpoint: discovered.endpoint
            )
        }
    }

    private func discoveredPeers(
        in results: Set<NWBrowser.Result>
    ) -> [UUID: (peer: PeerID, endpoint: NWEndpoint)] {
        var peers: [UUID: (peer: PeerID, endpoint: NWEndpoint)] = [:]

        for result in results {
            guard case .bonjour(let txtRecord) = result.metadata else {
                continue
            }

            guard let identifier = txtRecord["peerID"],
                  let peerID = UUID(uuidString: identifier),
                  peerID != localPeer.id else {
                continue
            }

            let displayName = txtRecord["name"] ?? serviceName(from: result.endpoint)
            peers[peerID] = (
                PeerID(id: peerID, displayName: displayName),
                result.endpoint
            )
        }

        return peers
    }

    private func serviceName(from endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }

        return "Peer"
    }

    private func connectIfNeeded(to peer: PeerID, endpoint: NWEndpoint) {
        guard isRunning, blockedPeers.contains(peer.id) == false else {
            return
        }

        guard localPeer.id.uuidString < peer.id.uuidString else {
            return
        }

        guard connections[peer.id] == nil else {
            return
        }

        guard pendingConnections.values.contains(where: { $0.expectedPeer == peer }) == false else {
            return
        }

        let connection = NWConnection(to: endpoint, using: makeTCPParameters())
        startReliableConnection(connection, isOutgoing: true, expectedPeer: peer)
    }

    private func startReliableConnection(
        _ connection: NWConnection,
        isOutgoing: Bool,
        expectedPeer: PeerID?
    ) {
        let context = ConnectionContext(
            connection: connection,
            isOutgoing: isOutgoing,
            expectedPeer: expectedPeer
        )
        pendingConnections[ObjectIdentifier(connection)] = context
        connection.stateUpdateHandler = { [weak self, weak context] state in
            guard let context else {
                return
            }

            Task { @MainActor in
                self?.handleReliableState(state, context: context)
            }
        }
        connection.start(queue: queue)
    }

    private func handleReliableState(
        _ state: NWConnection.State,
        context: ConnectionContext
    ) {
        switch state {
        case .ready:
            receiveFrame(on: context)
            sendHandshake(on: context.connection)

        case .failed(let error):
            print("Peer connection failed:", error)
            handleReliableConnectionEnded(context)

        case .cancelled:
            handleReliableConnectionEnded(context)

        default:
            break
        }
    }

    private func sendHandshake(on connection: NWConnection) {
        guard let body = try? encoder.encode(localPeer),
              let frame = makeFrame(type: .handshake, body: body) else {
            connection.cancel()
            return
        }

        connection.send(
            content: frame,
            completion: .contentProcessed { error in
                if let error {
                    print("Peer handshake failed:", error)
                }
            }
        )
    }

    private func receiveFrame(on context: ConnectionContext) {
        context.connection.receive(
            minimumIncompleteLength: Self.frameHeaderSize,
            maximumLength: Self.frameHeaderSize
        ) { [weak self, weak context] header, _, isComplete, error in
            guard let context else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    print("Peer frame header receive failed:", error)
                    context.connection.cancel()
                    return
                }

                guard isComplete == false,
                      let header,
                      header.count == Self.frameHeaderSize else {
                    context.connection.cancel()
                    return
                }

                let length = header.reduce(UInt32(0)) { partialResult, byte in
                    (partialResult << 8) | UInt32(byte)
                }

                guard length > 0, length <= Self.maximumFrameSize else {
                    context.connection.cancel()
                    return
                }

                self.receiveFrameBody(length: Int(length), on: context)
            }
        }
    }

    private func receiveFrameBody(length: Int, on context: ConnectionContext) {
        context.connection.receive(
            minimumIncompleteLength: length,
            maximumLength: length
        ) { [weak self, weak context] data, _, _, error in
            guard let context else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    print("Peer frame receive failed:", error)
                    context.connection.cancel()
                    return
                }

                guard let data, data.count == length else {
                    context.connection.cancel()
                    return
                }

                self.handleFrame(data, on: context)

                if context.connection.state == .ready {
                    self.receiveFrame(on: context)
                }
            }
        }
    }

    private func handleFrame(_ frame: Data, on context: ConnectionContext) {
        guard let typeByte = frame.first,
              let type = FrameType(rawValue: typeByte) else {
            context.connection.cancel()
            return
        }

        let body = Data(frame.dropFirst())

        switch type {
        case .handshake:
            handleHandshake(body, on: context)

        case .payload:
            guard let peer = context.peer,
                  connections[peer.id] === context else {
                context.connection.cancel()
                return
            }

            delegate?.peerNetworkSessionDidReceive(body, from: peer)
        }
    }

    private func handleHandshake(_ body: Data, on context: ConnectionContext) {
        guard context.peer == nil,
              let peer = try? decoder.decode(PeerID.self, from: body),
              peer.id != localPeer.id,
              blockedPeers.contains(peer.id) == false else {
            context.connection.cancel()
            return
        }

        if let expectedPeer = context.expectedPeer, expectedPeer.id != peer.id {
            context.connection.cancel()
            return
        }

        let shouldUseOutgoingConnection = localPeer.id.uuidString < peer.id.uuidString

        guard context.isOutgoing == shouldUseOutgoingConnection else {
            context.connection.cancel()
            return
        }

        if let existing = connections[peer.id], existing !== context {
            context.connection.cancel()
            return
        }

        context.peer = peer
        pendingConnections[ObjectIdentifier(context.connection)] = nil
        connections[peer.id] = context
        reconnectTasks[peer.id]?.cancel()
        reconnectTasks[peer.id] = nil
        delegate?.peerNetworkSessionDidConnect(peer)
    }

    private func handleReliableConnectionEnded(_ context: ConnectionContext) {
        pendingConnections[ObjectIdentifier(context.connection)] = nil

        guard let peer = context.peer,
              connections[peer.id] === context else {
            return
        }

        connections[peer.id] = nil
        delegate?.peerNetworkSessionDidDisconnect(peer)
        scheduleReconnect(to: peer.id)
    }

    private func scheduleReconnect(to peerID: UUID) {
        guard isRunning,
              blockedPeers.contains(peerID) == false,
              reconnectTasks[peerID] == nil,
              discoveredTCPPeers[peerID] != nil else {
            return
        }

        reconnectTasks[peerID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))

            guard Task.isCancelled == false,
                  let self,
                  let discovered = self.discoveredTCPPeers[peerID] else {
                return
            }

            self.reconnectTasks[peerID] = nil
            self.connectIfNeeded(to: discovered.peer, endpoint: discovered.endpoint)
        }
    }

    private func startOutgoingDatagramConnection(to peer: PeerID, endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: makeUDPParameters())
        udpConnections[peer.id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                switch state {
                case .ready:
                    self.datagramSender.setConnection(connection, for: peer.id)

                case .failed, .cancelled:
                    if self.udpConnections[peer.id] === connection {
                        self.udpConnections[peer.id] = nil
                        self.datagramSender.setConnection(nil, for: peer.id)
                    }

                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func startIncomingDatagramConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else {
                return
            }

            if state == .ready {
                Task { @MainActor in
                    self?.receiveDatagram(on: connection)
                }
            }
        }
        connection.start(queue: queue)
    }

    private func receiveDatagram(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let connection else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    print("Best-effort receive failed:", error)
                    connection.cancel()
                    return
                }

                if let data, data.count > 16 {
                    let identifierData = Data(data.prefix(16))
                    let identifier = identifierData.withUnsafeBytes { bytes -> UUID? in
                        guard let baseAddress = bytes.baseAddress else {
                            return nil
                        }

                        return NSUUID(
                            uuidBytes: baseAddress.assumingMemoryBound(to: UInt8.self)
                        ) as UUID
                    }

                    if let identifier,
                       let peer = self.connections[identifier]?.peer,
                       self.blockedPeers.contains(identifier) == false {
                        self.delegate?.peerNetworkSessionDidReceive(
                            Data(data.dropFirst(16)),
                            from: peer
                        )
                    }
                }

                if connection.state == .ready {
                    self.receiveDatagram(on: connection)
                }
            }
        }
    }

    private func makeFrame(type: FrameType, body: Data) -> Data? {
        let payload = Data([type.rawValue]) + body

        guard payload.count <= Self.maximumFrameSize,
              let length = UInt32(exactly: payload.count) else {
            return nil
        }

        let header = Data([
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])

        return header + payload
    }

    private func makeTCPParameters() -> NWParameters {
        let tls = makeTLSOptions()
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    private func makeUDPParameters() -> NWParameters {
        let parameters = NWParameters(
            dtls: makeTLSOptions(),
            udp: NWProtocolUDP.Options()
        )
        parameters.includePeerToPeer = true
        return parameters
    }

    private func makeTLSOptions() -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let securityOptions = options.securityProtocolOptions
        sec_protocol_options_set_local_identity(securityOptions, identity)
        sec_protocol_options_set_peer_authentication_required(securityOptions, true)
        sec_protocol_options_set_verify_block(
            securityOptions,
            { _, _, complete in
                complete(true)
            },
            queue
        )
        return options
    }
}
