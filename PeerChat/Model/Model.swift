import ScrechKit
@preconcurrency import MultipeerConnectivity
import SwiftoCrypto

@Observable
final class Model: NSObject {
    private let serviceType = "PeerChat"
    private let myPeerId = MCPeerID(displayName: ValueStore().nickname)
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    nonisolated(unsafe) private let session: MCSession
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private var invitedPeers: Set<MCPeerID> = []
    
    var connectedPeers: [MCPeerID] = []
    var chats: [DuoChat] = []
    
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
        
        let deviceId = UIDevice.current.identifierForVendor ?? UUID()
        
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
        
        session.cancelConnectPeer(peerID)
        
        chats.removeAll {
            $0.chat.peer == peerID
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
        
        let encryptedMessage = encryptedMessageData.base64EncodedString()
        
        let newMessage = ConnectMessage(
            messageType: .Message,
            message: Message(
                text: encryptedMessage,
                from: self.myPerson
            )
        )
        
        if !self.session.connectedPeers.isEmpty {
            do {
                if let data = try? self.encoder.encode(newMessage) {
                    if let newMessagePayload = newMessage.message,
                       let index = self.chats.firstIndex(where: { $0.person.id == chat.person.id }) {
                        self.chats[index].chat.messages.append(newMessagePayload)
                    }
                    
                    try self.session.send(data, toPeers: [chat.peer], with: .reliable)
                }
            } catch {
                print("Error for sending:", error.localizedDescription)
            }
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
            print("From MCPeerID:", from.displayName)
            print("Available chats:", chats)
            print("DeleteMessage content:", String(describing: info.deleteMessage))
            
            if let personKey = chats.first(where: { $0.chat.peer == from })?.person,
               let message = info.deleteMessage {
                let idToDelete = message.idToDelete
                
                print("Delete message", idToDelete.description)
                
                deleteMessage(idToDelete, person: personKey)
                
            } else {
                print("Could not delete message")
            }
        }
    }
    
    func deleteMessage(_ id: UUID, person: Person) {
        let index = chats.firstIndex(where: { $0.chat.messages.map(\.id).contains(id) })
        
        guard let index else { return }
        
        let msgIndex = chats[index].chat.messages.firstIndex(where: { $0.id == id })
        
        guard let msgIndex else { return }
        
        var updatedChat = chats[index]
        updatedChat.chat.messages.remove(at: msgIndex)
        
        withAnimation {
            chats[index] = updatedChat
        }
        
        sendDeleteRequest(id, to: person)
    }
    
    func handleCloseChat(from peer: MCPeerID) {
        print(peer.displayName, "has disconnected")
        
        session.disconnect()
        changeState.toggle()
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
        if chats.contains(where: { $0.person.id == person.id }) {
            return
        }
        
        print("New Person:", person.name)
        
        let newChat = DuoChat(person: person, chat: Chat(peer: from, person: person))
        chats.append(newChat)
    }
    
    func newMessage(
        message: Message,
        from: MCPeerID,
        size: Int
    ) {
        let timeInterval = max(Date().timeIntervalSince(message.date), 0.001)
        let speed = Double(size) / timeInterval / 1024
        
        print("New Message:", message.text)
        print("Speed: \(Int(speed)) KB/s")
        
        if let index = chats.firstIndex(where: { $0.person.id == message.from.id }) {
            chats[index].chat.messages.append(message)
        }
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
        }
        
        connectedPeers = session.connectedPeers
    }
    
    func didReceiveData(_ data: Data, from peerID: MCPeerID) {
        if let message = try? decoder.decode(ConnectMessage.self, from: data) {
            reciveInfo(
                info: message,
                from: peerID,
                size: data.count
            )
        }
    }
}
