import SwiftUI

struct MessageInfo: View {
    private var message: Message
    
    init(_ message: Message) {
        self.message = message
    }
    
    private var sender: Person {
        message.from
    }
    
    var body: some View {
        VStack {
            Text(message.text)
            
            Text(message.date, style: .date)
            
            Text(sender.name)
        }
    }
}

#Preview {
    MessageInfo(.init(
        text: "Some message",
        from: Person(
            .init(displayName: "Preview Device"),
            id: UUID(),
            publicKey: "",
            info: [:]
        )
    ))
}
