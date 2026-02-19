import ScrechKit

struct MessageInfo: View {
    private var message: Message
    private let fileSize: String?
    
    init(_ message: Message, fileSize: String? = nil) {
        self.message = message
        self.fileSize = fileSize
    }
    
    var body: some View {
        List {
            LabeledContent("Sender", value: message.from.name)
            LabeledContent("Type", value: message.contentType.rawValue.capitalized)
            
            if message.contentType == .text {
                LabeledContent("Text", value: message.text)
            }
            
            if let attachmentName = message.attachmentName {
                LabeledContent("Attachment", value: attachmentName)
            }
            
            if message.contentType == .file, let fileSize {
                LabeledContent("File Size", value: fileSize)
            }
            
            if let deliveryDurationText {
                LabeledContent("Delivery Duration", value: deliveryDurationText)
            }
            
            if let deliverySpeedText {
                LabeledContent("Delivery Speed", value: deliverySpeedText)
            }
            
            LabeledContent {
                HStack(spacing: 5) {
                    Text(message.date, style: .date)
                    Text(message.date, style: .time)
                }
            } label: {
                Text("Date")
            }
        }
    }
    
    private var deliveryDurationText: String? {
        guard let deliveryDuration = message.deliveryDuration else {
            return nil
        }
        
        let seconds = max(deliveryDuration, 0)
        let formattedSeconds = seconds.formatted(
            .number.precision(.fractionLength(1))
        )
        
        return "\(formattedSeconds)s"
    }
    
    private var deliverySpeedText: String? {
        guard let deliveryDuration = message.deliveryDuration,
              let deliverySizeBytes = message.deliverySizeBytes else {
            return nil
        }
        
        let speedBytesPerSecond = Double(deliverySizeBytes) / max(deliveryDuration, 0.001)
        
        return "\(formatBytes(Int64(speedBytesPerSecond)))/s"
    }
}

#Preview {
    MessageInfo(.preview)
}
