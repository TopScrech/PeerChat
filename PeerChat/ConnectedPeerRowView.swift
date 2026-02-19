import SwiftUI
import ScrechKit
@preconcurrency import MultipeerConnectivity

struct ConnectedPeerRowView: View {
    @Environment(Model.self) private var model
    let peer: MCPeerID
    
    var body: some View {
        HStack {
            Text(model.displayName(for: peer))
            
            Spacer()
            
            if model.isActiveChat(with: peer) {
                Button("Open", systemImage: "bubble.left.and.bubble.right") {
                    model.openChat(with: peer)
                }
                
            } else if model.hasPendingOutgoingChatRequest(to: peer) {
                Label("Requested", systemImage: "clock")
                    .secondary()
                
            } else if model.hasIncomingChatRequest(from: peer) {
                Label("Awaiting response", systemImage: "questionmark.bubble")
                    .secondary()
            } else {
                Button("Request", systemImage: "paperplane") {
                    model.requestChat(with: peer)
                }
            }
        }
    }
}
