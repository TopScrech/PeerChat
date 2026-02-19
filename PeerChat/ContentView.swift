import SwiftUI
import SwiftoCrypto

struct ContentView: View {
    @Environment(Model.self) private var model
    @Environment(CryptoModel.self) private var crypto
    @State private var path: [UUID] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chats")
                        Spacer()
                        ProgressView()
                    }
                    .padding(.horizontal)
                    
                    if model.connectedPeers.isEmpty {
                        Text("No Peers")
                            .padding(.horizontal)
                    } else {
                        ForEach(model.connectedPeers, id: \.self) {
                            ConnectedPeerRowView(peer: $0)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
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
                #if os(macOS)
                ToolbarItem {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                #endif
            }
        }
    }
}
