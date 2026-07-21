import Foundation
@preconcurrency import Network

nonisolated final class PeerDatagramSender: @unchecked Sendable {
    private let lock = NSLock()
    private let localPeerID: UUID
    private var connections: [UUID: NWConnection] = [:]

    init(localPeerID: UUID) {
        self.localPeerID = localPeerID
    }

    func setConnection(_ connection: NWConnection?, for peerID: UUID) {
        lock.lock()
        connections[peerID] = connection
        lock.unlock()
    }

    func removeAllConnections() {
        lock.lock()
        connections.removeAll()
        lock.unlock()
    }

    func send(_ data: Data, to peerID: UUID) {
        lock.lock()
        let connection = connections[peerID]
        lock.unlock()

        guard let connection else {
            return
        }

        var uuid = localPeerID.uuid
        let identifier = withUnsafeBytes(of: &uuid) { Data($0) }
        let datagram = identifier + data

        guard datagram.count <= connection.maximumDatagramSize else {
            return
        }

        connection.send(
            content: datagram,
            completion: .contentProcessed { error in
                if let error {
                    print("Best-effort send failed:", error)
                }
            }
        )
    }
}
