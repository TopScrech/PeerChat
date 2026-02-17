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
    
    private var peerStatus: String? {
        if let status = person.info?["Status"], !status.isEmpty {
            return status
        }
        
        return nil
    }
    
    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollView in
                VStack {
                    ScrollView {
                        VStack(spacing: 4) {
                            if let chat = model.chats.first(where: { $0.person.id == person.id })?.chat {
                                ForEach(chat.messages, id: \.id) {
                                    MessageRow($0, person: person, geo: geo)
                                        .environment(crypto)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .onChange(of: model.chats.first(where: { $0.person.id == person.id })?.chat.messages) {
                        if let last = model.chats.first(where: { $0.person.id == person.id })?.chat.messages.last {
                            withAnimation(.spring) {
                                scrollView.scrollTo(last.id)
                            }
                        } else {
                            print("Scroll wasn't possible")
                        }
                    }
                    
                    MessageComposer(person: person, proxy: scrollView)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            crypto.receivedPublicKey = crypto.stringToPublicKey(person.publicKey)
        }
        .navigationTitle(person.name)
        .navSubtitle(peerStatus ?? "")
        .onChange(of: model.changeState) {
            dismiss()
        }
        .toolbar {
            Button("Disconnect") {
                dismiss()
                model.disconnectPeer(person.id)
            }
        }
    }
}

#Preview {
    ChatView(.init(.init(displayName: "Preview"), id: UUID(), publicKey: "1234567890", info: ["Test": "Test"]))
        .environment(Model(CryptoModel()))
        .environment(CryptoModel())
}
