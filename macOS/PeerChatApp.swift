import SwiftUI

@main
struct PeerChatApp: App {
    @StateObject private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
