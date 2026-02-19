import SwiftUI

struct MessageInfo: View {
    private var message: Message
    
    init(_ message: Message) {
        self.message = message
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
}

#Preview {
    MessageInfo(.preview)
}
