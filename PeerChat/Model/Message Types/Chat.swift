import MultipeerConnectivity

struct Chat {
    var messages: [Message] = []
    var peer: MCPeerID
    var person: Person
    var id = UUID()
}

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
}
