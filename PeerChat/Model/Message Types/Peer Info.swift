import Foundation

struct PeerInfo: Codable {
    enum PeerInfoType: Codable {
        case Person
    }
    
    var peerInfoType: PeerInfoType = .Person
}
