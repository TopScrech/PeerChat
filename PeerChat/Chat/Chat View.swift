import ScrechKit
import SwiftoCrypto

struct ChatView: View {
    @Environment(CryptoModel.self) private var crypto
    @Environment(Model.self) private var model
    @Environment(\.dismiss) private var dismiss
    
    private let person: Person
    
    init(_ person: Person) {
        self.person = person
    }
    
    @State private var newMessage = ""
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollView in
                VStack {
                    Text(person.info?.description ?? "No info")
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            if let chat = model.chats.first(where: { $0.person.id == person.id })?.chat {
                                ForEach(chat.messages, id: \.id) { message in
                                    MessageRow(message, person: person, geo: geometry)
                                        .environment(crypto)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .onChange(of: model.chats.first(where: { $0.person.id == person.id })?.chat.messages) { _, _ in
                        main {
                            if let last = model.chats.first(where: { $0.person.id == person.id })?.chat.messages.last {
                                withAnimation(.spring) {
                                    scrollView.scrollTo(last.id)
                                }
                            } else {
                                print("Scroll wasn't possible")
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Enter a message", text: $newMessage)
                            .onSubmit {
                                sendMessage(scrollView)
                                newMessage = ""
                            }
                            .textFieldStyle(.roundedBorder)
                            .animation(.spring(), value: newMessage)
                            .padding(.horizontal)
                        
                        if !newMessage.isEmpty {
                            Button {
                                sendMessage(scrollView)
                                newMessage = ""
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .bold()
                                    .fontSize(24)
                                    .foregroundColor(.blue)
                            }
                            .animation(.spring, value: newMessage)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            crypto.receivedPublicKey = crypto.stringToPublicKey(person.publicKey)
        }
        .onChange(of: model.changeState) { _, _ in
            dismiss()
        }
        .toolbar {
            Button("Disconnect") {
                dismiss()
                model.disconnectPeer(person.id)
            }
        }
    }
    
    func sendMessage(_ proxy: ScrollViewProxy) {
        if !newMessage.isEmpty {
            if let index = model.chats.firstIndex(where: { $0.person.id == person.id }) {
                model.send(newMessage, chat: model.chats[index].chat)
                newMessage = ""
                
                if let last = model.chats[index].chat.messages.last {
                    withAnimation(.spring) {
                        proxy.scrollTo(last.id)
                    }
                }
            }
        }
    }
}

#Preview {
    ChatView(.init(.init(displayName: "Preview"), id: UUID(), publicKey: "1234567890", info: ["Test": "Test"]))
        .environment(Model(CryptoModel()))
        .environment(CryptoModel())
}
