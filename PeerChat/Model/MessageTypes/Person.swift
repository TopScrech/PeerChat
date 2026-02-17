import MultipeerConnectivity

struct Person: Codable, Equatable {
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

extension Person {
    private static let previewId = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    
    static let preview = Person(
        MCPeerID(displayName: "Preview Device"),
        id: previewId,
        publicKey: "1234567890",
        info: [
            "Status": "Available"
        ]
    )
}
