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
    MessageInfo(.preview)
}
