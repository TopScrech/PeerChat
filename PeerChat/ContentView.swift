import SwiftUI
import SwiftoCrypto

struct ContentView: View {
    @Environment(Model.self) private var model
    @Environment(CryptoModel.self) private var crypto
    
    var body: some View {
        NavigationView {
            List {
                Section("Chats") {
                    if model.chats.isEmpty {
                        ContentUnavailableView("No Chats", systemImage: "mail.stack", description: Text("123"))
                    } else {
                        ForEach(model.chats, id: \.chat.id) { duoChat in
                            NavigationLink(duoChat.chat.peer.displayName) {
                                ChatView(duoChat.person)
                                    .environment(model)
                                    .environment(crypto)
                                    .navigationTitle(duoChat.person.name)
                            }
                        }
                    }
                }
                
                Section {
                    if model.connectedPeers.isEmpty {
                        Text("No Peers")
                    } else {
                        ForEach(model.connectedPeers, id: \.hash) {
                            Text($0.displayName)
                        }
                    }
                } header: {
                    HStack {
                        Text("Near-By Peers")
                        
                        Spacer()
                        
                        ProgressView()
                    }
                }
                
                Button("Restart") {
                    model.restartConnections()
                }
                
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
        }
    }
}
