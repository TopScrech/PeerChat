import Foundation

struct ConnectMessage: Codable {
    enum MessageType: Codable {
        case Message
        case PeerInfo
        case CloseChat
        case DeleteMessage
    }
    
    var messageType: MessageType = .Message
    var peerInfo: Person? = nil
    var message: Message? = nil
    var deleteMessage: DeleteMessage? = nil
}
