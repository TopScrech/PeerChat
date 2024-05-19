import SwiftUI

struct MessageInfo: View {
    private var message: Message
    
    init(_ message: Message) {
        self.message = message
    }
        
    var body: some View {
        List {
            Text(message.text)
            
            HStack {
                Text(message.date, style: .date)
                
                Text(message.date, style: .time)
            }
            
            Text(message.from.name)
        }
    }
}

#Preview {
    MessageInfo(
        Message(
            text: "Some message",
            from: Person(
                .init(displayName: "Preview Device"),
                id: UUID(),
                publicKey: "1234567890",
                info: [:]
            )
        )
    )
}
