import Foundation

struct PeerID: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
}

extension PeerID: Hashable {
    static func == (lhs: PeerID, rhs: PeerID) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
