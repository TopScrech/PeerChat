import Foundation

struct DeleteMessage: Codable {
    let idToDelete: UUID
    
    init(_ id: UUID) {
        self.idToDelete = id
    }
}
