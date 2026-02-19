import ScrechKit
@preconcurrency import MultipeerConnectivity

struct ConnectedPeerRowView: View {
    @Environment(Model.self) private var model
    let peer: MCPeerID
    private let rowHeight: CGFloat = 56
    
    var body: some View {
        HStack {
            Text(model.displayName(for: peer))
            
            Spacer()
            
            if model.hasIncomingChatRequest(from: peer) {
                HStack {
                    SFButton("checkmark") {
                        model.respondToChatRequest(from: peer, accept: true)
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.green, in: .circle)
                    
                    SFButton("xmark") {
                        model.respondToChatRequest(from: peer, accept: false)
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red, in: .circle)
                }
                
            } else if model.isActiveChat(with: peer) {
                SFButton("bubble.left.and.bubble.right") {
                    model.openChat(with: peer)
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Open Chat")
                
            } else if model.hasPendingOutgoingChatRequest(to: peer) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Request") {
                    model.requestChat(with: peer)
                }
            }
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
    }
}
