#if os(iOS)
import AVFoundation
import CallKit
import Foundation

@MainActor
protocol SystemCallManagerDelegate: AnyObject {
    func systemCallManagerDidStartCall(_ callID: UUID)
    func systemCallManagerDidAnswerCall(_ callID: UUID)
    func systemCallManagerDidEndCall(_ callID: UUID)
    func systemCallManagerDidReset()
}

@MainActor
final class SystemCallManager: NSObject {
    weak var delegate: SystemCallManagerDelegate?
    
    private let provider: CXProvider
    private let callController = CXCallController()
    
    override init() {
        let config = CXProviderConfiguration()
        config.supportedHandleTypes = [.generic]
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.includesCallsInRecents = false
        
        provider = CXProvider(configuration: config)
        
        super.init()
        
        provider.setDelegate(self, queue: nil)
    }
    
    func requestStartCall(
        callID: UUID,
        handle: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let action = CXStartCallAction(call: callID, handle: CXHandle(type: .generic, value: handle))
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { [weak self] error in
            Task { @MainActor in
                if error == nil {
                    self?.provider.reportOutgoingCall(with: callID, startedConnectingAt: Date())
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
    
    func requestEndCall(
        callID: UUID,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let action = CXEndCallAction(call: callID)
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { error in
            Task { @MainActor in
                completion(error == nil)
            }
        }
    }
    
    func reportIncomingCall(
        callID: UUID,
        handle: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.localizedCallerName = handle
        update.hasVideo = false
        
        provider.reportNewIncomingCall(with: callID, update: update) { error in
            Task { @MainActor in
                completion(error == nil)
            }
        }
    }
    
    func reportOutgoingConnected(callID: UUID) {
        provider.reportOutgoingCall(with: callID, connectedAt: Date())
    }
    
    func reportEnded(callID: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: callID, endedAt: Date(), reason: reason)
    }
}

extension SystemCallManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor [weak self] in
            self?.delegate?.systemCallManagerDidReset()
        }
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let callID = action.callUUID
        action.fulfill()
        
        Task { @MainActor [weak self] in
            self?.delegate?.systemCallManagerDidStartCall(callID)
        }
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let callID = action.callUUID
        action.fulfill()
        
        Task { @MainActor [weak self] in
            self?.delegate?.systemCallManagerDidAnswerCall(callID)
        }
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let callID = action.callUUID
        action.fulfill()
        
        Task { @MainActor [weak self] in
            self?.delegate?.systemCallManagerDidEndCall(callID)
        }
    }
}
#endif
