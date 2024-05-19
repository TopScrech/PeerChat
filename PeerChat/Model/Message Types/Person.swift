import MultipeerConnectivity

struct Person: Codable {
    let name: String
    let publicKey: String
    let id: UUID
    let info: [String: String]?
    
    init(
        _ peer: MCPeerID,
        id: UUID,
        publicKey: String,
        info: [String: String]?
    ) {
        self.name = peer.displayName
        self.id = id
        self.publicKey = publicKey
        self.info = info
    }
}
