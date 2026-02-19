import Foundation

struct ChatRequest: Codable {
    var id = UUID()
}

struct ChatRequestResponse: Codable {
    var requestID: UUID
    var isAccepted: Bool
}
