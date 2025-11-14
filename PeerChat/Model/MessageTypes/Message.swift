import Foundation

struct Message: Codable {
    let text: String
    let from: Person
    let id: UUID
    let date: Date
    let replyOnId: UUID?
    
    init(
        text: String,
        from: Person,
        replyOnId: UUID? = nil
    ) {
        self.text = text
        self.from = from
        self.id = UUID()
        self.date = Date()
        self.replyOnId = replyOnId
    }
}
