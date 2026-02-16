import ScrechKit

struct MessageComposer: View {
    @Environment(Model.self) private var model
    
    private let person: Person
    private let proxy: ScrollViewProxy
    
    @State private var message = ""
    
    init(person: Person, proxy: ScrollViewProxy) {
        self.person = person
        self.proxy = proxy
    }
    
    var body: some View {
        HStack {
            TextField("Enter a message", text: $message)
                .onSubmit(onSend)
                .textFieldStyle(.roundedBorder)
                .animation(.spring(), value: message)
                .padding(.horizontal)
            
            if !message.isEmpty {
                Button("Send", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .bold()
                    .fontSize(24)
                    .foregroundColor(.blue)
                    .animation(.spring, value: message)
            }
        }
        .padding()
    }
    
    private func onSend() {
        guard !message.isEmpty else { return }
        
        guard let index = model.chats.firstIndex(where: { $0.person.id == person.id }) else { return }
        model.send(message, chat: model.chats[index].chat)
        message = ""
        
        if let last = model.chats[index].chat.messages.last {
            withAnimation(.spring) {
                proxy.scrollTo(last.id)
            }
        }
    }
}
