import Foundation

struct ConnectMessage: Codable {
    enum MessageType: Codable {
        case Message,
             PeerInfo,
             CloseChat,
             DeleteMessage
    }
    
    var messageType: MessageType = .Message
    var peerInfo: Person? = nil
    var message: Message? = nil
    var deleteMessage: DeleteMessage? = nil
}
