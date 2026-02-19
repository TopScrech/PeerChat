import SwiftUI

struct MessageInfo: View {
    private var message: Message
    
    init(_ message: Message) {
        self.message = message
    }
    
    var body: some View {
        List {
            Text("Type: \(message.contentType.rawValue.capitalized)")
            
            if message.contentType == .text {
                Text(message.text)
            }
            
            if let attachmentName = message.attachmentName {
                Text(attachmentName)
            }
            
            HStack {
                Text(message.date, style: .date)
                Text(message.date, style: .time)
            }
            
            Text(message.from.name)
        }
    }
}

#Preview {
    MessageInfo(.preview)
}
