import SwiftUI
import SwiftoCrypto

struct ContentView: View {
    @Environment(Model.self) private var model
    @Environment(CryptoModel.self) private var crypto
    @State private var path: [UUID] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Chats") {
                    if model.activeChats.isEmpty {
                        ContentUnavailableView(
                            "No Chats",
                            systemImage: "ellipsis.message",
                            description: Text("Send a chat request to start a conversation")
                        )
                    } else {
                        ForEach(model.activeChats, id: \.chat.id) { duoChat in
                            NavigationLink(value: duoChat.person.id) {
                                Text(duoChat.person.name)
                            }
                        }
                    }
                }
                
                if !model.incomingChatPeers.isEmpty {
                    Section("Incoming Chat Requests") {
                        ForEach(model.incomingChatPeers, id: \.self) { peer in
                            IncomingChatRequestRowView(peer: peer)
                        }
                    }
                }
                
                Section {
                    if model.connectedPeers.isEmpty {
                        Text("No Peers")
                    } else {
                        ForEach(model.connectedPeers, id: \.self) { peer in
                            ConnectedPeerRowView(peer: peer)
                        }
                    }
                } header: {
                    HStack {
                        Text("Near-By Peers")
                        
                        Spacer()
                        
                        ProgressView()
                    }
                }
            }
            .navigationDestination(for: UUID.self) { personID in
                if let person = model.chats.first(where: { $0.person.id == personID })?.person {
                    ChatView(person)
                        .environment(model)
                        .environment(crypto)
                } else {
                    ContentUnavailableView(
                        "Chat Unavailable",
                        systemImage: "ellipsis.bubble",
                        description: Text("This chat is no longer available")
                    )
                }
            }
            .onChange(of: model.chatRouteID) { _, routeID in
                guard let routeID else {
                    return
                }
                
                if path.last != routeID {
                    path.append(routeID)
                }
                
                model.consumeChatRoute()
            }
            .refreshable {
                model.restartConnections()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        }
    }
}
