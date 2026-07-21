import Foundation

struct Chat {
    var id = UUID()
    
    var messages: [Message] = []
    var peer: PeerID
    var person: Person
}
