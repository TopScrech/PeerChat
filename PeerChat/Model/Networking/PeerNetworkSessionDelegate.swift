import Foundation

@MainActor
protocol PeerNetworkSessionDelegate: AnyObject {
    func peerNetworkSessionDidConnect(_ peer: PeerID)
    func peerNetworkSessionDidDisconnect(_ peer: PeerID)
    func peerNetworkSessionDidReceive(_ data: Data, from peer: PeerID)
}
