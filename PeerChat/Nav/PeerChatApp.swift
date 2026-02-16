import ScrechKit

@main
struct PeerChatApp: App {
    @StateObject private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            Container()
                .environmentObject(store)
        }
    }
}
