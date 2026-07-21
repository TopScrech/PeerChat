import ScrechKit

@main
struct PeerChatApp: App {
    @State private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            Container()
                .environment(store)
        }
    }
}
