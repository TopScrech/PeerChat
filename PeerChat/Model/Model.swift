import ScrechKit
@preconcurrency import AVFoundation
import Observation
@preconcurrency import MultipeerConnectivity
import SwiftoCrypto
#if os(iOS)
import CallKit
#endif

private final class CallConversionInputSource {
    nonisolated(unsafe) private var didProvideBuffer = false
    nonisolated(unsafe) private let buffer: AVAudioPCMBuffer
    
    nonisolated init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
    
    nonisolated func nextBuffer(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideBuffer {
            status.pointee = .noDataNow
            return nil
        }
        
        didProvideBuffer = true
        status.pointee = .haveData
        return buffer
    }
}

@Observable
final class Model: NSObject {
    enum CallState: String {
        case idle, dialing, ringing, active
    }
    
    private enum SessionPayloadType: UInt8 {
        case control = 1
        case voipAudio = 2
    }
    
    private enum CallAudioPipelineError: Error {
        case unsupportedCaptureFormat
    }
    
    private enum SystemCallEndReason {
        case remoteEnded, failed, unanswered
    }
    
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
    @ObservationIgnored private let callCaptureEngine = AVAudioEngine()
    @ObservationIgnored private let callRenderEngine = AVAudioEngine()
    @ObservationIgnored private let callPlayerNode = AVAudioPlayerNode()
    @ObservationIgnored private var callRenderConfigured = false
    @ObservationIgnored private let callAudioFormat: AVAudioFormat
    @ObservationIgnored private var callID: UUID?
    @ObservationIgnored private var hasSentCallStart = false
    private var callCaptureMuted = false
#if os(iOS)
    @ObservationIgnored private var isSystemCallManaged = false
    @ObservationIgnored private var isSystemAudioSessionActive = false
    @ObservationIgnored private var hasPendingCallActivation = false
    @ObservationIgnored private var pendingCallActivationWasDialing = false
#endif
#if os(iOS)
    @ObservationIgnored private let systemCallManager = SystemCallManager()
#endif
    
    var connectedPeers: [MCPeerID] = []
    var chats: [DuoChat] = []
    var chatRouteID: UUID?
    var callState: CallState = .idle
    var callPeerID: MCPeerID?
    var isMicrophoneMuted = false
    
    var myPerson: Person
    var crypto: CryptoModel
    var changeState = false
    
    init(_ crypto: CryptoModel) {
        self.crypto = crypto
        
        guard let callAudioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000.0,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create call audio format")
        }
        
        self.callAudioFormat = callAudioFormat
        
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
#if os(iOS)
        systemCallManager.delegate = self
#endif
        
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
        
        if callPeerID == peerID {
            finishCurrentCall(
                notifyRemote: true,
                reportToSystem: true,
                systemEndReason: .failed
            )
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
    
    var callDisplayName: String {
        guard let callPeerID else {
            return ""
        }
        
        return displayName(for: callPeerID)
    }
    
    func isInCall(with person: Person) -> Bool {
        guard callState != .idle else {
            return false
        }
        
        return chats.first(where: { $0.person.id == person.id })?.chat.peer == callPeerID
    }
    
    func startCall(with person: Person) {
        guard callState == .idle else {
            return
        }
        
        guard let chat = chats.first(where: { $0.person.id == person.id })?.chat else {
            return
        }
        
        guard session.connectedPeers.contains(chat.peer) else {
            return
        }
        
        callPeerID = chat.peer
        callState = .dialing
        hasSentCallStart = false
        isMicrophoneMuted = false
        callCaptureMuted = false
#if os(iOS)
        isSystemCallManaged = false
        isSystemAudioSessionActive = false
        hasPendingCallActivation = false
        pendingCallActivationWasDialing = false
#endif
        
        let newCallID = UUID()
        callID = newCallID
        
#if os(iOS)
        let displayName = displayName(for: chat.peer)
        
        systemCallManager.requestStartCall(callID: newCallID, handle: displayName) { [weak self] success in
            guard let self else {
                return
            }
            
            guard self.callID == newCallID else {
                return
            }
            
            guard self.callPeerID == chat.peer else {
                return
            }
            
            if success {
                self.isSystemCallManaged = true
                return
            }
            
            self.sendCallStart(to: chat.peer)
        }
#else
        sendCallStart(to: chat.peer)
#endif
    }
    
    func endCall() {
        guard callPeerID != nil else {
            return
        }
        
#if os(iOS)
        if isSystemCallManaged, let callID {
            systemCallManager.requestEndCall(callID: callID) { [weak self] success in
                guard let self else {
                    return
                }
                
                guard self.callID == callID else {
                    return
                }
                
                if success {
                    return
                }
                
                self.finishCurrentCall(notifyRemote: true, reportToSystem: false)
            }
            
            return
        }
#endif
        
        finishCurrentCall(notifyRemote: true, reportToSystem: false)
    }

    func toggleMicrophoneMuted() {
        let nextValue = isMicrophoneMuted == false
        isMicrophoneMuted = nextValue
        callCaptureMuted = nextValue
    }
    
    private func acceptCall() {
        guard callState == .ringing else {
            return
        }
        
        guard let callPeerID else {
            return
        }
        
        sendControlMessage(
            ConnectMessage(messageType: .CallAccept),
            to: [callPeerID]
        )
        
        activateCallSession()
    }
    
    private func sendCallStart(to peer: MCPeerID) {
        guard callState == .dialing else {
            return
        }
        
        guard hasSentCallStart == false else {
            return
        }
        
        hasSentCallStart = true
        
        sendControlMessage(
            ConnectMessage(messageType: .CallStart),
            to: [peer]
        )
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
        
        sendControlMessage(requestMessage, to: [peer])
        outgoingChatRequestIDs[peer] = request.id
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
        
        sendControlMessage(closeMessage, to: [peer])
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
        
        sendControlMessage(deleteMessage, to: [peer])
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
        
        if let index = chats.firstIndex(where: { $0.person.id == chat.person.id }) {
            chats[index].chat.messages.append(message)
        }
        
        sendControlMessage(newMessage, to: [chat.peer])
    }
    
    private func sendControlMessage(
        _ message: ConnectMessage,
        to peers: [MCPeerID],
        mode: MCSessionSendDataMode = .reliable
    ) {
        guard peers.isEmpty == false else {
            return
        }
        
        do {
            let body = try encoder.encode(message)
            sendPayload(body, type: .control, to: peers, mode: mode)
        } catch {
            print("Control message encode failed:", error.localizedDescription)
        }
    }
    
    private func sendPayload(
        _ body: Data,
        type: SessionPayloadType,
        to peers: [MCPeerID],
        mode: MCSessionSendDataMode
    ) {
        guard peers.isEmpty == false else {
            return
        }
        
        var payload = Data([type.rawValue])
        payload.append(body)
        
        do {
            try session.send(payload, toPeers: peers, with: mode)
        } catch {
            print("Session send failed:", error.localizedDescription)
        }
    }
    
    private func decodePayload(_ data: Data) -> (type: SessionPayloadType, body: Data)? {
        guard let kindByte = data.first else {
            return nil
        }
        
        guard let type = SessionPayloadType(rawValue: kindByte) else {
            return nil
        }
        
        return (type, Data(data.dropFirst()))
    }
    
    private func receiveCallStart(from peer: MCPeerID) {
        guard session.connectedPeers.contains(peer) else {
            return
        }
        
        if let callPeerID, callPeerID != peer {
            return
        }
        
        callPeerID = peer
        
        guard callState != .active else {
            return
        }
        
        if callState == .dialing {
            sendControlMessage(
                ConnectMessage(messageType: .CallAccept),
                to: [peer]
            )
            
            activateCallSession()
            return
        }
        
        callState = .ringing
#if os(iOS)
        hasPendingCallActivation = false
        pendingCallActivationWasDialing = false
        isSystemAudioSessionActive = false
#endif

#if os(iOS)
        let incomingCallID = callID ?? UUID()
        callID = incomingCallID
        
        systemCallManager.reportIncomingCall(
            callID: incomingCallID,
            handle: displayName(for: peer)
        ) { [weak self] success in
            guard let self else {
                return
            }
            
            guard self.callID == incomingCallID else {
                return
            }
            
            if success {
                self.isSystemCallManaged = true
                return
            }
            
            self.isSystemCallManaged = false
            self.acceptCall()
        }
#else
        acceptCall()
#endif
    }
    
    private func receiveCallAccepted(from peer: MCPeerID) {
        guard callPeerID == peer else {
            return
        }
        
        guard callState == .dialing else {
            return
        }
        
        activateCallSession()
    }
    
    private func activateCallSession() {
        guard callPeerID != nil else {
            return
        }
        
        guard callState != .active else {
            return
        }

#if os(iOS)
        if isSystemCallManaged {
            hasPendingCallActivation = true
            pendingCallActivationWasDialing = callState == .dialing
            activatePendingSystemCallIfPossible()
            return
        }
#endif

        activateCallPipelines(wasDialing: callState == .dialing)
    }

#if os(iOS)
    private func activatePendingSystemCallIfPossible() {
        guard hasPendingCallActivation else {
            return
        }

        guard isSystemCallManaged else {
            return
        }

        guard isSystemAudioSessionActive else {
            return
        }

        let wasDialing = pendingCallActivationWasDialing
        hasPendingCallActivation = false
        pendingCallActivationWasDialing = false
        activateCallPipelines(wasDialing: wasDialing)
    }
#endif

    private func activateCallPipelines(wasDialing: Bool) {
        
        do {
            try configureCallAudioSession()
            try startCallRenderPipeline()
            try startCallCapturePipeline()
            callState = .active
#if os(iOS)
            if wasDialing, isSystemCallManaged, let callID {
                systemCallManager.reportOutgoingConnected(callID: callID)
            }
#endif
        } catch {
            print("Call audio setup failed:", error.localizedDescription)
            finishCurrentCall(
                notifyRemote: true,
                reportToSystem: true,
                systemEndReason: .failed
            )
        }
    }
    
    private func configureCallAudioSession() throws {
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        do {
            try audioSession.setPreferredSampleRate(callAudioFormat.sampleRate)
        } catch {
            print("Failed to set preferred sample rate:", error.localizedDescription)
        }

        do {
            try audioSession.setPreferredIOBufferDuration(0.02)
        } catch {
            print("Failed to set preferred IO buffer duration:", error.localizedDescription)
        }

        if isSystemCallManaged == false {
            try audioSession.setActive(true)
        }
#endif
    }
    
    private func startCallRenderPipeline() throws {
        if callRenderConfigured == false {
            callRenderEngine.attach(callPlayerNode)
            callRenderEngine.connect(callPlayerNode, to: callRenderEngine.mainMixerNode, format: callAudioFormat)
            callRenderConfigured = true
        }
        
        if callRenderEngine.isRunning == false {
            callRenderEngine.prepare()
            try callRenderEngine.start()
        }
        
        if callPlayerNode.isPlaying == false {
            callPlayerNode.play()
        }
    }
    
    private func startCallCapturePipeline() throws {
        guard let callPeerID else {
            return
        }
        
        let inputNode = callCaptureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outputFormat = callAudioFormat
        let session = self.session
        
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        if converter == nil && Self.formatsMatch(inputFormat, outputFormat) == false {
            throw CallAudioPipelineError.unsupportedCaptureFormat
        }
        
        let tapHandler = Self.makeCaptureTapHandler(
            session: session,
            peerID: callPeerID,
            converter: converter,
            outputFormat: outputFormat,
            isMuted: { [weak self] in
                guard let self else {
                    return false
                }

                return self.callCaptureMuted
            }
        )
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tapHandler)
        
        if callCaptureEngine.isRunning == false {
            callCaptureEngine.prepare()
            try callCaptureEngine.start()
        }
    }
    
    private func stopCallAudioPipelines(deactivateAudioSession: Bool) {
        callCaptureEngine.inputNode.removeTap(onBus: 0)
        callCaptureEngine.stop()
        callRenderEngine.stop()
        callPlayerNode.stop()
        
#if os(iOS)
        if deactivateAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session:", error.localizedDescription)
            }
        }
#endif
    }
    
    private func finishCurrentCall(
        notifyRemote: Bool,
        reportToSystem: Bool,
        systemEndReason: SystemCallEndReason = .remoteEnded
    ) {
        let currentPeerID = callPeerID
        let currentCallID = callID
#if os(iOS)
        let currentSystemCallManaged = isSystemCallManaged
#endif
        
        if notifyRemote, let currentPeerID {
            sendControlMessage(
                ConnectMessage(messageType: .CallEnd),
                to: [currentPeerID]
            )
        }
        
#if os(iOS)
        let shouldDeactivateAudioSession = currentSystemCallManaged == false
#else
        let shouldDeactivateAudioSession = false
#endif

        stopCallAudioPipelines(deactivateAudioSession: shouldDeactivateAudioSession)
        callState = .idle
        callPeerID = nil
        callID = nil
        hasSentCallStart = false
        isMicrophoneMuted = false
        callCaptureMuted = false
#if os(iOS)
        isSystemCallManaged = false
        isSystemAudioSessionActive = false
        hasPendingCallActivation = false
        pendingCallActivationWasDialing = false
#endif
        
#if os(iOS)
        if reportToSystem, currentSystemCallManaged, let currentCallID {
            systemCallManager.reportEnded(
                callID: currentCallID,
                reason: mapSystemEndReason(systemEndReason)
            )
        }
#endif
    }
    
#if os(iOS)
    private func mapSystemEndReason(_ reason: SystemCallEndReason) -> CXCallEndedReason {
        switch reason {
        case .remoteEnded:
            .remoteEnded
        case .failed:
            .failed
        case .unanswered:
            .unanswered
        }
    }
#endif
    
    nonisolated private static func sendCallAudioPayload(
        _ audioData: Data,
        to peerID: MCPeerID,
        session: MCSession
    ) {
        var payload = Data([SessionPayloadType.voipAudio.rawValue])
        payload.append(audioData)
        
        do {
            try session.send(payload, toPeers: [peerID], with: .unreliable)
        } catch {
            print("Session send failed:", error.localizedDescription)
        }
    }
    
    nonisolated private static func makeCaptureTapHandler(
        session: MCSession,
        peerID: MCPeerID,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat,
        isMuted: @escaping () -> Bool
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            if isMuted() {
                return
            }

            guard let audioData = Self.makeCallAudioData(
                from: buffer,
                converter: converter,
                outputFormat: outputFormat
            ) else {
                return
            }
            
            Self.sendCallAudioPayload(audioData, to: peerID, session: session)
        }
    }
    
    nonisolated private static func makeCallAudioData(
        from inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) -> Data? {
        let buffer: AVAudioPCMBuffer
        
        if let converter {
            let frameRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
            let outputFrameCapacity = max(
                AVAudioFrameCount(Double(inputBuffer.frameLength) * frameRatio) + 1,
                1
            )
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                return nil
            }
            
            let inputSource = CallConversionInputSource(buffer: inputBuffer)
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                inputSource.nextBuffer(status: outStatus)
            }
            
            guard status == .haveData || status == .inputRanDry else {
                return nil
            }
            
            buffer = convertedBuffer
        } else {
            buffer = inputBuffer
        }
        
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }
        
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(buffer.frameLength) * bytesPerFrame
        
        return Data(bytes: channelData[0], count: byteCount)
    }
    
    nonisolated private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat &&
        lhs.sampleRate == rhs.sampleRate &&
        lhs.channelCount == rhs.channelCount &&
        lhs.isInterleaved == rhs.isInterleaved
    }
    
    private func receiveCallAudio(_ data: Data, from peer: MCPeerID) {
        guard callState == .active else {
            return
        }
        
        guard callPeerID == peer else {
            return
        }
        
        let bytesPerFrame = Int(callAudioFormat.streamDescription.pointee.mBytesPerFrame)
        let frameLength = AVAudioFrameCount(data.count / bytesPerFrame)
        
        guard frameLength > 0 else {
            return
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: callAudioFormat, frameCapacity: frameLength) else {
            return
        }
        
        guard let channelData = buffer.int16ChannelData else {
            return
        }
        
        buffer.frameLength = frameLength
        data.copyBytes(
            to: UnsafeMutableRawBufferPointer(
                start: channelData[0],
                count: data.count
            )
        )
        
        if callRenderEngine.isRunning == false {
            try? callRenderEngine.start()
        }
        
        if callPlayerNode.isPlaying == false {
            callPlayerNode.play()
        }
        
        callPlayerNode.scheduleBuffer(buffer)
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
            
        case .CallStart:
            receiveCallStart(from: from)
            
        case .CallAccept:
            receiveCallAccepted(from: from)
            
        case .CallEnd:
            guard callPeerID == from else {
                return
            }
            
            finishCurrentCall(
                notifyRemote: false,
                reportToSystem: true,
                systemEndReason: .remoteEnded
            )
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
        
        withAnimation {
            chats[chatIndex].chat.messages.removeAll()
        }
        
        for id in messageIDs {
            sendDeleteRequest(id, to: person)
        }
    }
    
    func handleCloseChat(from peer: MCPeerID) {
        print(peer.displayName, "has disconnected")
        
        if callPeerID == peer {
            finishCurrentCall(
                notifyRemote: false,
                reportToSystem: true,
                systemEndReason: .remoteEnded
            )
        }
        
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
        
        sendControlMessage(response, to: [peer])
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
        
        sendControlMessage(newMessage, to: [peer])
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

nonisolated extension Model: MCNearbyServiceAdvertiserDelegate {
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
        finishCurrentCall(
            notifyRemote: true,
            reportToSystem: true,
            systemEndReason: .failed
        )
        
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

nonisolated extension Model: MCNearbyServiceBrowserDelegate {
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

nonisolated extension Model: MCSessionDelegate {
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

#if os(iOS)
@MainActor
extension Model: SystemCallManagerDelegate {
    func systemCallManagerDidStartCall(_ callID: UUID) {
        guard self.callID == callID else {
            return
        }
        
        guard let callPeerID else {
            return
        }
        
        sendCallStart(to: callPeerID)
    }
    
    func systemCallManagerDidAnswerCall(_ callID: UUID) {
        guard self.callID == callID else {
            return
        }
        
        acceptCall()
    }
    
    func systemCallManagerDidEndCall(_ callID: UUID) {
        guard self.callID == callID else {
            return
        }
        
        finishCurrentCall(notifyRemote: true, reportToSystem: false)
    }
    
    func systemCallManagerDidReset() {
        guard callPeerID != nil else {
            return
        }
        
        isSystemAudioSessionActive = false
        finishCurrentCall(notifyRemote: false, reportToSystem: false)
    }

    func systemCallManagerDidActivateAudioSession() {
        isSystemAudioSessionActive = true
        activatePendingSystemCallIfPossible()
    }

    func systemCallManagerDidDeactivateAudioSession() {
        isSystemAudioSessionActive = false
    }
}
#endif

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
            
            if callPeerID == peerID {
                finishCurrentCall(
                    notifyRemote: false,
                    reportToSystem: true,
                    systemEndReason: .failed
                )
            }
        }
        
        connectedPeers = session.connectedPeers
    }
    
    func didReceiveData(_ data: Data, from peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID) else {
            print("Ignoring data from disconnected peer:", peerID.displayName)
            return
        }
        
        if let payload = decodePayload(data) {
            switch payload.type {
            case .control:
                if let message = try? decoder.decode(ConnectMessage.self, from: payload.body) {
                    reciveInfo(
                        info: message,
                        from: peerID,
                        size: payload.body.count
                    )
                }
                
            case .voipAudio:
                receiveCallAudio(payload.body, from: peerID)
            }
            
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
