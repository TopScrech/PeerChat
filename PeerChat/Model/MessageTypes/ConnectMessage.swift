import Foundation

struct ConnectMessage: Codable {
    enum MessageType: Codable {
        case Message,
             PeerInfo,
             CloseChat,
             DeleteMessage,
             ChatRequest,
             ChatRequestResponse
    }
    
    var messageType: MessageType = .Message
    var peerInfo: Person? = nil
    var message: Message? = nil
    var deleteMessage: DeleteMessage? = nil
    var chatRequest: ChatRequest? = nil
    var chatRequestResponse: ChatRequestResponse? = nil
}
