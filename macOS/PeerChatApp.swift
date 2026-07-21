import SwiftUI

@main
struct PeerChatApp: App {
    @State private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
        }
    }
}
