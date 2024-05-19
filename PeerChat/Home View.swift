import SwiftUI
import SwiftoCrypto

struct HomeView: View {
    private var crypto: CryptoModel
    private var model: Model
    
    init() {
        crypto = CryptoModel()
        model = Model(crypto)
    }
    
    var body: some View {
        TabView {
            ContentView()
                .tag("Chats")
                .tabItem {
                    Label("Chats", systemImage: "ellipsis.bubble")
                }
            
            ProfileView()
                .tag("Profile")
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .environment(model)
        .environment(crypto)
    }
}

#Preview {
    HomeView()
}
