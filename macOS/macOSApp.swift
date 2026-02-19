import SwiftUI

@main
struct macOSApp: App {
    @StateObject private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
