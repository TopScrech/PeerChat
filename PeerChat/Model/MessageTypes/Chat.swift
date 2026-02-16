import MultipeerConnectivity

struct Chat {
    var id = UUID()
    
    var messages: [Message] = []
    var peer: MCPeerID
    var person: Person
}
