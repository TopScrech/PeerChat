import MultipeerConnectivity

struct Chat {
    var id = UUID()
    
    var messages: [Message] = []
    var peer: MCPeerID
    var person: Person
}

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}
