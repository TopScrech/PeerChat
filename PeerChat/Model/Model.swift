import ScrechKit
import MultipeerConnectivity
import SwiftoCrypto

@Observable
final class Model: NSObject {
    private let serviceType = "PeerChat"
    private let myPeerId = MCPeerID(displayName: SettingsView().nickname)
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let session: MCSession
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    
    var connectedPeers: [MCPeerID] = []
    var chats: [DuoChat] = []
    
    var myPerson: Person
    var crypto: CryptoModel
    var changeState = false
    
    init(_ crypto: CryptoModel) {
        self.crypto = crypto
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: ["Status": SettingsView().status], serviceType: serviceType)
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        myPerson = Person(session.myPeerID, id: UIDevice.current.identifierForVendor!, publicKey: crypto.publicKeyToString(crypto.publicKey), info: ["Status": SettingsView().status])
        
        super.init()
        
        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self
        
        serviceAdvertiser.startAdvertisingPeer()
        serviceBrowser.startBrowsingForPeers()
    }
    
    func disconnectPeer(_ uuid: UUID) {
        let duoChat = chats.first(where: { $0.person.id == uuid })
        
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
            print("Error sending close chat message: \(error)")
        }
    }
    
    func sendDeleteRequest(_ id: UUID, to person: Person) {
        let deleteMessageContent = DeleteMessage(id)
        
        let deleteMessage = ConnectMessage(
            messageType: .DeleteMessage,
            deleteMessage: deleteMessageContent
        )
        
        let duoChat = chats.first(where: { $0.person.id == person.id })
        
        guard let duoChat else {
            return
        }
        
        let peer = duoChat.chat.peer
        
        do {
            let data = try encoder.encode(deleteMessage)
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("Error sending delete message: \(error)")
        }
    }
    
    func send(_ messageText: String, chat: Chat) {
        print("Sent \"\(messageText)\" to \(chat.peer.displayName)")
        
        let encryptedMessageData = crypto.encrypt(messageText, using: crypto.stringToPublicKey(crypto.publicKeyToString(crypto.receivedPublicKey!))!)
        let encryptedMessage = encryptedMessageData!.base64EncodedString()
        
        main {
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
                        if let index = self.chats.firstIndex(where: { $0.person.id == chat.person.id }) {
                            main {
                                self.chats[index].chat.messages.append(newMessage.message!)
                            }
                        }
                        try self.session.send(data, toPeers: [chat.peer], with: .reliable)
                    }
                } catch {
                    print("Error for sending: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func reciveInfo(info: ConnectMessage, from: MCPeerID, size: Int) {
        print("Received info: \(info.messageType)")
        
        switch info.messageType {
        case .Message:
            newMessage(
                message: info.message!, 
                from: from,
                size: size
            )
            
        case .PeerInfo:
            newPerson(
                person: info.peerInfo!, 
                from: from
            )
            
        case .CloseChat:
            handleCloseChat(from: from)
            
        case .DeleteMessage:
            print("From MCPeerID: \(from.displayName)")
            print("Available chats: \(chats)")
            print("DeleteMessage content: \(String(describing: info.deleteMessage))")
            
            if let personKey = chats.first(where: { $0.chat.peer == from })?.person,
               let message = info.deleteMessage {
                let idToDelete = message.idToDelete
                
                print("Delete message \(idToDelete.description)")
                
                deleteMessage(idToDelete, person: personKey)
                
            } else {
                print("Could not delete message")
            }
        }
    }
    
    func deleteMessage(_ id: UUID, person: Person) {
        let index = chats.firstIndex(where: { $0.chat.messages.map(\.id).contains(id) })
        
        guard let index else {
            return
        }
        
        let msgIndex = chats[index].chat.messages.firstIndex(where: { $0.id == id })
        
        guard let msgIndex else {
            return
        }
        
        var updatedChat = chats[index]
        updatedChat.chat.messages.remove(at: msgIndex)
        
        withAnimation {
            chats[index] = updatedChat
        }
        
        sendDeleteRequest(id, to: person)
    }
    
    func handleCloseChat(from peer: MCPeerID) {
        print("\(peer.displayName) has disconnected")
        
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
        print("New Connection: \(peer.displayName)")
        
        let newMessage = ConnectMessage(messageType: .PeerInfo, peerInfo: self.myPerson)
        
        do {
            if let data = try? encoder.encode(newMessage) {
                try session.send(data, toPeers: [peer], with: .reliable)
            }
        } catch {
            print("Error for newConnection: \(String(describing: error))")
        }
    }
    
    func newPerson(person: Person, from: MCPeerID) {
        print("New Person: \(person.name)")
        
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
        
        print("""
            New Message: \(message.text)
            Speed: \(Int(speed)) KB/s
        """)
        
        if let index = chats.firstIndex(where: { $0.person.id == message.from.id }) {
            chats[index].chat.messages.append(message)
        }
    }
}

extension Model: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        print("Advertiser didNotStartAdvertisingPeer: \(error.localizedDescription)")
    }
    
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        print("didReceiveInvitationFromPeer \(peerID)")
        
        main {
            invitationHandler(true, self.session)
        }
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
    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error)
    {
        print("ServiceBrowser didNotStartBrowsingForPeers: \(String(describing: error))")
    }
    
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        print("ServiceBrowser found peer: \(peerID)")
        
        main {
            browser.invitePeer(
                peerID,
                to: self.session,
                withContext: nil,
                timeout: 10
            )
        }
    }
    
    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        print("ServiceBrowser lost peer: \(peerID)")
    }
}

extension Model: MCSessionDelegate {
    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        print("peer \(peerID) didChangeState: \(state.rawValue)")
        
        main {
            if state == .connected {
                self.newConnection(peer: peerID)
            }
            
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        if let message = try? decoder.decode(ConnectMessage.self, from: data) {
            main {
                self.reciveInfo(info: message, from: peerID, size: data.count)
            }
        }
    }
    
    public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        print("Receiving streams is not supported")
    }
    
    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        print("Receiving resources is not supported")
    }
    
    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        print("Receiving resources is not supported")
    }
}
