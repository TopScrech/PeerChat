import SwiftUI
@preconcurrency import MultipeerConnectivity

struct IncomingChatRequestRowView: View {
    @Environment(Model.self) private var model
    let peer: MCPeerID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.displayName(for: peer))
            
            HStack {
                Button("Accept", systemImage: "checkmark.circle") {
                    model.respondToChatRequest(from: peer, accept: true)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Decline", systemImage: "xmark.circle") {
                    model.respondToChatRequest(from: peer, accept: false)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
