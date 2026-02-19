import Foundation

struct Message: Codable, Equatable {
    enum ContentType: String, Codable {
        case text, voice, file
    }
    
    let text: String
    let from: Person
    let id: UUID
    let date: Date
    let contentType: ContentType
    let attachmentName: String?
    let attachmentType: String?
    let attachmentData: Data?
    let voiceDuration: TimeInterval?
    let replyOnId: UUID?
    var deliveryDuration: TimeInterval?
    var deliverySizeBytes: Int?
    
    init(
        text: String,
        from: Person,
        replyOnId: UUID? = nil
    ) {
        self.text = text
        self.from = from
        self.id = UUID()
        self.date = Date()
        self.contentType = .text
        self.attachmentName = nil
        self.attachmentType = nil
        self.attachmentData = nil
        self.voiceDuration = nil
        self.replyOnId = replyOnId
        self.deliveryDuration = nil
        self.deliverySizeBytes = nil
    }
    
    init(
        voiceData: Data,
        duration: TimeInterval,
        from: Person,
        fallbackText: String = ""
    ) {
        self.text = fallbackText
        self.from = from
        self.id = UUID()
        self.date = Date()
        self.contentType = .voice
        self.attachmentName = "Voice Message.m4a"
        self.attachmentType = "audio/m4a"
        self.attachmentData = voiceData
        self.voiceDuration = duration
        self.replyOnId = nil
        self.deliveryDuration = nil
        self.deliverySizeBytes = nil
    }
    
    init(
        fileData: Data,
        fileName: String,
        fileType: String?,
        from: Person,
        fallbackText: String = ""
    ) {
        self.text = fallbackText
        self.from = from
        self.id = UUID()
        self.date = Date()
        self.contentType = .file
        self.attachmentName = fileName
        self.attachmentType = fileType
        self.attachmentData = fileData
        self.voiceDuration = nil
        self.replyOnId = nil
        self.deliveryDuration = nil
        self.deliverySizeBytes = nil
    }
    
    enum CodingKeys: String, CodingKey {
        case text
        case from
        case id
        case date
        case contentType
        case attachmentName
        case attachmentType
        case attachmentData
        case voiceDuration
        case replyOnId
        case deliveryDuration
        case deliverySizeBytes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        text = try container.decode(String.self, forKey: .text)
        from = try container.decode(Person.self, forKey: .from)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        contentType = try container.decodeIfPresent(ContentType.self, forKey: .contentType) ?? .text
        attachmentName = try container.decodeIfPresent(String.self, forKey: .attachmentName)
        attachmentType = try container.decodeIfPresent(String.self, forKey: .attachmentType)
        attachmentData = try container.decodeIfPresent(Data.self, forKey: .attachmentData)
        voiceDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .voiceDuration)
        replyOnId = try container.decodeIfPresent(UUID.self, forKey: .replyOnId)
        deliveryDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .deliveryDuration)
        deliverySizeBytes = try container.decodeIfPresent(Int.self, forKey: .deliverySizeBytes)
    }
}

extension Message {
    static let preview = Message(
        text: "Some message",
        from: .preview
    )
}
