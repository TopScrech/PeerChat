import ScrechKit

@main
struct PeerChat: App {
    @StateObject private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            Container()
                .environmentObject(store)
        }
    }
}
