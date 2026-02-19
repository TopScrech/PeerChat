import SwiftUI
import ScrechKit

struct MessageRow: View {
    @Environment(Model.self) private var model
    
    private let message: Message
    private let person: Person
    private let geo: GeometryProxy
    
    init(_ message: Message, person: Person, geo: GeometryProxy) {
        self.message = message
        self.person = person
        self.geo = geo
    }
    
    private var isCurrentUser: Bool {
        message.from.id == model.myPerson.id
    }
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer(minLength: geo.size.width * 0.2)
            }
            
            VStack {
                MessageContentView(
                    message: message,
                    isCurrentUser: isCurrentUser
                )
                
                Text(message.date, format: .dateTime)
                    .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                    .secondary()
                    .footnote()
            }
            
            if !isCurrentUser {
                Spacer(minLength: geo.size.width * 0.2)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            NavigationLink("Info") {
                MessageInfo(message)
            }
            
            if isCurrentUser {
                Button("Delete", role: .destructive) {
                    model.deleteMessage(message.id, person: person)
                }
            }
        }
    }
}

//#Preview {
//    GeometryReader { geo in
//        MessageRow(
//            Message(
//                text: "Preview",
//                from: Person(
//                    MCPeerID(displayName: "Preview Device"),
//                    id: UUID(),
//                    publicKey: "1234567890",
//                    info: [:]
//                )
//            ),
//            geo: geo
//        )
//    }
//}
