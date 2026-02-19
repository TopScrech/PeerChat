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
        ContentView()
            .environment(model)
            .environment(crypto)
    }
}

#Preview {
    HomeView()
}
