import SwiftUI
import MultipeerConnectivity
import SwiftoCrypto

struct MessageRow: View {
    @Environment(Model.self) private var model
    @Environment(CryptoModel.self) private var crypto
    
    private let message: Message
    private let person: Person
    private let geo: GeometryProxy
    
    init(
        _ message: Message,
        person: Person,
        geo: GeometryProxy
    ) {
        self.message = message
        self.person = person
        self.geo = geo
    }
    
    var isCurrentUser: Bool {
        message.from.id == model.myPerson.id
    }
    
    var decryptedMessage: String? {
        guard let encryptedData = Data(base64Encoded: message.text) else {
            print("Invalid encrypted text")
            return nil
        }
        
        return crypto.decrypt(encryptedData, using: crypto.privateKey)
    }
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer(minLength: geo.size.width * 0.2)
            }
            
            VStack {
                if let decryptedMessage {
                    if !decryptedMessage.trimmingCharacters(in: .whitespacesAndNewlines).containsOnlyEmoji {
                        Text(decryptedMessage)
                            .foregroundColor(isCurrentUser ? .white : .primary)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(
                                isCurrentUser ? .blue : .secondary,
                                in: .rect(cornerRadius: 20, style: .continuous)
                            )
                    } else {
                        Text(decryptedMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                            .fontSize(40)
                            .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                            .padding()
                    }
                }
                
                Text(message.date, format: .dateTime)
                    .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                    .foregroundStyle(.secondary)
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
            
            Button("Delete", role: .destructive) {
                model.deleteMessage(message.id, person: person)
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
