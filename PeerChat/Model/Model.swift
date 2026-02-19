import ScrechKit
@preconcurrency import MultipeerConnectivity
import SwiftoCrypto

@Observable
final class Model: NSObject {
    private let serviceType = "PeerChat"
    let maxAttachmentBytes = 10 * 1024 * 1024
    private let myPeerId = MCPeerID(displayName: ValueStore().nickname)
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    nonisolated(unsafe) private let session: MCSession
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private var invitedPeers: Set<MCPeerID> = []
    private var outgoingChatRequestIDs: [MCPeerID: UUID] = [:]
    private var incomingChatRequestIDs: [MCPeerID: UUID] = [:]
    private var pendingActivationPeers: Set<MCPeerID> = []
    
    var connectedPeers: [MCPeerID] = []
    var chats: [DuoChat] = []
    var chatRouteID: UUID?
    
    var myPerson: Person
    var crypto: CryptoModel
    var changeState = false
    
    init(_ crypto: CryptoModel) {
        self.crypto = crypto
        
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: ["Status": ValueStore().status],
            serviceType: serviceType
        )
        
        serviceBrowser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        
        let deviceId = ValueStore().deviceID
        
        myPerson = Person(
            session.myPeerID,
            id: deviceId,
            publicKey: crypto.publicKeyToString(crypto.publicKey),
            info: [
                "Status": ValueStore().status
            ]
        )
        
        super.init()
        
        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self
        
        serviceAdvertiser.startAdvertisingPeer()
        serviceBrowser.startBrowsingForPeers()
    }
    
    func disconnectPeer(_ uuid: UUID) {
        let duoChat = chats.first {
            $0.person.id == uuid
        }
        
        guard let duoChat else {
            return
        }
        
        let peerID = duoChat.chat.peer
        
        sendCloseChatMessage(to: peerID)
        
        if let index = connectedPeers.firstIndex(of: peerID) {
            connectedPeers.remove(at: index)
        }
        
        clearChatRequests(for: peerID)
        
        session.cancelConnectPeer(peerID)
        
        chats.removeAll {
            $0.chat.peer == peerID
        }
    }
    
    var activeChats: [DuoChat] {
        chats.filter(\.isActive)
    }
    
    var incomingChatPeers: [MCPeerID] {
        incomingChatRequestIDs
            .keys
            .sorted {
                displayName(for: $0) < displayName(for: $1)
            }
    }
    
    func displayName(for peer: MCPeerID) -> String {
        chats.first(where: { $0.chat.peer == peer })?.person.name ?? peer.displayName
    }
    
    func hasPendingOutgoingChatRequest(to peer: MCPeerID) -> Bool {
        outgoingChatRequestIDs[peer] != nil
    }
    
    func hasIncomingChatRequest(from peer: MCPeerID) -> Bool {
        incomingChatRequestIDs[peer] != nil
    }
    
    func isActiveChat(with peer: MCPeerID) -> Bool {
        chats.first(where: { $0.chat.peer == peer })?.isActive == true
    }
    
    func openChat(with peer: MCPeerID) {
        guard let chat = chats.first(where: { $0.chat.peer == peer }) else {
            return
        }
        
        guard chat.isActive else {
            return
        }
        
        chatRouteID = chat.person.id
    }
    
    func consumeChatRoute() {
        chatRouteID = nil
    }
    
    func requestChat(with peer: MCPeerID) {
        guard connectedPeers.contains(peer) else {
            return
        }
        
        if isActiveChat(with: peer) {
            openChat(with: peer)
            return
        }
        
        guard outgoingChatRequestIDs[peer] == nil else {
            return
        }
        
        let request = ChatRequest()
        
        let requestMessage = ConnectMessage(
            messageType: .ChatRequest,
            chatRequest: request
        )
        
        do {
            let data = try encoder.encode(requestMessage)
            try session.send(data, toPeers: [peer], with: .reliable)
            outgoingChatRequestIDs[peer] = request.id
        } catch {
            print("Error sending chat request:", error)
        }
    }
    
    func respondToChatRequest(from peer: MCPeerID, accept: Bool) {
        guard let requestID = incomingChatRequestIDs[peer] else {
            return
        }
        
        sendChatRequestResponse(to: peer, requestID: requestID, accept: accept)
        incomingChatRequestIDs[peer] = nil
        
        if accept {
            activateChat(with: peer, shouldRoute: true)
        }
    }
    
    func sendCloseChatMessage(to peer: MCPeerID) {
        let closeMessage = ConnectMessage(messageType: .CloseChat, peerInfo: nil, message: nil)
        
        do {
            let data = try encoder.encode(closeMessage)
            
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("Error sending close chat message:", error)
        }
    }
    
    func sendDeleteRequest(_ id: UUID, to person: Person) {
        let deleteMessageContent = DeleteMessage(id)
        
        let deleteMessage = ConnectMessage(
            messageType: .DeleteMessage,
            deleteMessage: deleteMessageContent
        )
        
        let duoChat = chats.first {
            $0.person.id == person.id
        }
        
        guard let duoChat else { return }
        
        let peer = duoChat.chat.peer
        
        do {
            let data = try encoder.encode(deleteMessage)
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("Error sending delete message:", error)
        }
    }
    
    func send(_ messageText: String, chat: Chat) {
        print("Sent \"\(messageText)\" to", chat.peer.displayName)
        
        guard let receivedPublicKey = crypto.receivedPublicKey else {
            print("Missing peer public key")
            return
        }
        
        guard let encryptedMessageData = crypto.encrypt(messageText, using: receivedPublicKey) else {
            print("Could not encrypt message")
            return
        }
        
        sendMessage(
            Message(
                text: encryptedMessageData.base64EncodedString(),
                from: myPerson
            ),
            chat: chat
        )
    }
    
    func sendVoiceMessage(_ voiceData: Data, duration: TimeInterval, chat: Chat) {
        guard voiceData.count <= maxAttachmentBytes else {
            print("Voice message is too large")
            return
        }
        
        guard let encryptedAudio = crypto.encryptAttachment(voiceData) else {
            print("Could not encrypt voice message")
            return
        }
        
        sendMessage(
            Message(
                voiceData: encryptedAudio,
                duration: duration,
                from: myPerson
            ),
            chat: chat
        )
    }
    
    func sendFile(
        _ fileData: Data,
        fileName: String,
        fileType: String?,
        chat: Chat
    ) {
        guard fileData.count <= maxAttachmentBytes else {
            print("File is too large")
            return
        }
        
        guard let encryptedData = crypto.encryptAttachment(fileData) else {
            print("Could not encrypt file")
            return
        }
        
        sendMessage(
            Message(
                fileData: encryptedData,
                fileName: fileName,
                fileType: fileType,
                from: myPerson
            ),
            chat: chat
        )
    }
    
    private func sendMessage(_ message: Message, chat: Chat) {
        let newMessage = ConnectMessage(
            messageType: .Message,
            message: message
        )
        
        guard !session.connectedPeers.isEmpty else {
            return
        }
        
        do {
            if let data = try? encoder.encode(newMessage) {
                if let index = chats.firstIndex(where: { $0.person.id == chat.person.id }) {
                    chats[index].chat.messages.append(message)
                }
                
                try session.send(data, toPeers: [chat.peer], with: .reliable)
            }
        } catch {
            print("Error for sending:", error.localizedDescription)
        }
    }
    
    func reciveInfo(info: ConnectMessage, from: MCPeerID, size: Int) {
        print("Received info:", info.messageType)
        
        switch info.messageType {
        case .Message:
            guard let message = info.message else {
                print("Missing message payload")
                return
            }
            
            newMessage(
                message: message,
                from: from,
                size: size
            )
            
        case .PeerInfo:
            guard let peerInfo = info.peerInfo else {
                print("Missing peer info payload")
                return
            }
            
            newPerson(
                person: peerInfo,
                from: from
            )
            
        case .CloseChat:
            handleCloseChat(from: from)
            
        case .DeleteMessage:
            guard let person = chats.first(where: { $0.chat.peer == from })?.person else {
                print("Ignoring delete request from unknown peer:", from.displayName)
                return
            }
            
            guard let deletePayload = info.deleteMessage else {
                print("Missing delete message payload")
                return
            }
            
            deleteMessage(
                deletePayload.idToDelete,
                person: person,
                initiatedByLocalUser: false
            )
            
        case .ChatRequest:
            guard let request = info.chatRequest else {
                print("Missing chat request payload")
                return
            }
            
            if isActiveChat(with: from) {
                sendChatRequestResponse(to: from, requestID: request.id, accept: true)
                openChat(with: from)
                return
            }
            
            incomingChatRequestIDs[from] = request.id
            
        case .ChatRequestResponse:
            guard let response = info.chatRequestResponse else {
                print("Missing chat request response payload")
                return
            }
            
            handleChatRequestResponse(response, from: from)
        }
    }
    
    func deleteMessage(
        _ id: UUID,
        person: Person,
        initiatedByLocalUser: Bool = true
    ) {
        guard let chatIndex = chats.firstIndex(where: { $0.person.id == person.id }) else {
            return
        }
        
        guard let messageIndex = chats[chatIndex].chat.messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        let message = chats[chatIndex].chat.messages[messageIndex]
        let isAuthorizedDelete = true
        
        guard isAuthorizedDelete else {
            print("Unauthorized delete request for message:", id)
            return
        }
        
        _ = withAnimation {
            chats[chatIndex].chat.messages.remove(at: messageIndex)
        }
        
        if initiatedByLocalUser {
            sendDeleteRequest(id, to: person)
        }
    }

    func clearAllMessages(for person: Person) {
        guard let chatIndex = chats.firstIndex(where: { $0.person.id == person.id }) else {
            return
        }

        let messageIDs = chats[chatIndex].chat.messages.map(\.id)

        guard !messageIDs.isEmpty else {
            return
        }

        _ = withAnimation {
            chats[chatIndex].chat.messages.removeAll()
        }

        for id in messageIDs {
            sendDeleteRequest(id, to: person)
        }
    }
    
    func handleCloseChat(from peer: MCPeerID) {
        print(peer.displayName, "has disconnected")
        
        session.disconnect()
        clearChatRequests(for: peer)
        changeState.toggle()
    }
    
    private func handleChatRequestResponse(_ response: ChatRequestResponse, from peer: MCPeerID) {
        guard let requestID = outgoingChatRequestIDs[peer] else {
            return
        }
        
        guard requestID == response.requestID else {
            return
        }
        
        outgoingChatRequestIDs[peer] = nil
        
        if response.isAccepted {
            activateChat(with: peer, shouldRoute: true)
        }
    }
    
    private func sendChatRequestResponse(to peer: MCPeerID, requestID: UUID, accept: Bool) {
        let response = ConnectMessage(
            messageType: .ChatRequestResponse,
            chatRequestResponse: ChatRequestResponse(
                requestID: requestID,
                isAccepted: accept
            )
        )
        
        do {
            let data = try encoder.encode(response)
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("Error sending chat response:", error)
        }
    }
    
    private func activateChat(with peer: MCPeerID, shouldRoute: Bool) {
        if let chatIndex = chats.firstIndex(where: { $0.chat.peer == peer }) {
            chats[chatIndex].isActive = true
            
            if shouldRoute {
                chatRouteID = chats[chatIndex].person.id
            }
            
            return
        }
        
        pendingActivationPeers.insert(peer)
    }
    
    private func clearChatRequests(for peer: MCPeerID) {
        outgoingChatRequestIDs[peer] = nil
        incomingChatRequestIDs[peer] = nil
        pendingActivationPeers.remove(peer)
    }
    
    //    func reciveInfo(info: ConnectMessage, from: MCPeerID) {
    //        print("Recived Info", info.messageType)
    //
    //        if info.messageType == .Message {
    //            newMessage(message: info.message!, from:from)
    //        }
    //
    //        if info.messageType == .PeerInfo {
    //            newPerson(person: info.peerInfo!, from:from)
    //        }
    //    }
    
    func newConnection(peer: MCPeerID) {
        print("New Connection:", peer.displayName)
        
        let newMessage = ConnectMessage(messageType: .PeerInfo, peerInfo: self.myPerson)
        
        do {
            if let data = try? encoder.encode(newMessage) {
                try session.send(data, toPeers: [peer], with: .reliable)
            }
        } catch {
            print("Error for newConnection:", String(describing: error))
        }
    }
    
    func newPerson(person: Person, from: MCPeerID) {
        if let index = chats.firstIndex(where: { $0.chat.peer == from }) {
            chats[index].person = person
            chats[index].chat.person = person
            
            if pendingActivationPeers.remove(from) != nil {
                chats[index].isActive = true
                chatRouteID = person.id
            }
            
            return
        }
        
        if let existingIndex = chats.firstIndex(where: { $0.person.id == person.id }) {
            let existingPeer = chats[existingIndex].chat.peer
            
            guard !session.connectedPeers.contains(existingPeer) else {
                print("Rejecting duplicate identity from a different connected peer")
                return
            }
            
            chats[existingIndex].person = person
            chats[existingIndex].chat.peer = from
            chats[existingIndex].chat.person = person
            
            if pendingActivationPeers.remove(from) != nil {
                chats[existingIndex].isActive = true
                chatRouteID = person.id
            }
            
            return
        }
        
        print("New Person:", person.name)
        
        let newChat = DuoChat(person: person, chat: Chat(peer: from, person: person))
        chats.append(newChat)
        
        if let newChatIndex = chats.firstIndex(where: { $0.chat.peer == from }),
           pendingActivationPeers.remove(from) != nil {
            chats[newChatIndex].isActive = true
            chatRouteID = person.id
        }
    }
    
    func newMessage(
        message: Message,
        from: MCPeerID,
        size: Int
    ) {
        guard let chatIndex = chats.firstIndex(where: { $0.chat.peer == from }) else {
            print("Ignoring message from unknown peer:", from.displayName)
            return
        }
        
        guard chats[chatIndex].person.id == message.from.id else {
            print("Rejecting message with mismatched sender identity from:", from.displayName)
            return
        }
        
        let deliveryDuration = max(Date().timeIntervalSince(message.date), 0)
        let speedBytesPerSecond = Double(size) / max(deliveryDuration, 0.001)
        
        var receivedMessage = message
        receivedMessage.deliveryDuration = deliveryDuration
        receivedMessage.deliverySizeBytes = size
        
        print("New Message:", message.text)
        print("Speed: \(Int(speedBytesPerSecond / 1024)) KB/s")
        
        chats[chatIndex].chat.messages.append(receivedMessage)
    }
}

extension Model: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        print("Advertiser didNotStartAdvertisingPeer:", error.localizedDescription)
    }
    
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerId: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        print("didReceiveInvitationFromPeer", peerId)
        
        invitationHandler(true, session)
    }
}

extension Model {
    func restartConnections() {
        serviceBrowser.stopBrowsingForPeers()
        
        serviceAdvertiser.stopAdvertisingPeer()
        
        session.disconnect()
        
        chats.removeAll()
        connectedPeers.removeAll()
        outgoingChatRequestIDs.removeAll()
        incomingChatRequestIDs.removeAll()
        pendingActivationPeers.removeAll()
        chatRouteID = nil
        
        // Start browsing and advertising again
        serviceAdvertiser.startAdvertisingPeer()
        serviceBrowser.startBrowsingForPeers()
    }
}

extension Model: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error)
    {
        print("ServiceBrowser didNotStartBrowsingForPeers:", String(describing: error))
    }
    
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor [weak self] in
            self?.foundPeer(peerID)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.invitedPeers.remove(peerID)
        }
        
        print("ServiceBrowser lost peer:", peerID)
    }
}

extension Model: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor [weak self] in
            self?.didChangePeerState(peerID: peerID, state: state)
        }
    }
    
    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        Task { @MainActor [weak self] in
            self?.didReceiveData(data, from: peerID)
        }
    }
    
    nonisolated public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        print("Receiving streams is not supported")
    }
    
    nonisolated public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        print("Receiving resources is not supported")
    }
    
    nonisolated public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        print("Receiving resources is not supported")
    }
}

@MainActor
private extension Model {
    func foundPeer(_ peerID: MCPeerID) {
        guard peerID != myPeerId else {
            return
        }
        
        guard !session.connectedPeers.contains(peerID) else {
            return
        }
        
        guard invitedPeers.insert(peerID).inserted else {
            return
        }
        
        print("ServiceBrowser found peer:", peerID)
        
        serviceBrowser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 10
        )
    }
    
    func didChangePeerState(peerID: MCPeerID, state: MCSessionState) {
        print("peer", peerID, "didChangeState:", state.rawValue)
        
        if state == .connected {
            newConnection(peer: peerID)
        }
        
        if state == .notConnected {
            invitedPeers.remove(peerID)
            clearChatRequests(for: peerID)
        }
        
        connectedPeers = session.connectedPeers
    }
    
    func didReceiveData(_ data: Data, from peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID) else {
            print("Ignoring data from disconnected peer:", peerID.displayName)
            return
        }
        
        if let message = try? decoder.decode(ConnectMessage.self, from: data) {
            reciveInfo(
                info: message,
                from: peerID,
                size: data.count
            )
        }
    }
}

extension Model {
    static func preview(_ crypto: CryptoModel = .preview) -> Model {
        Model(crypto)
    }
}

extension CryptoModel {
    static var preview: CryptoModel {
        CryptoModel()
    }
}
