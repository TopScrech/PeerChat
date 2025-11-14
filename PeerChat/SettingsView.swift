import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ValueStore
    
    var body: some View {
        List {
            TextField("Nickname", text: $store.nickname)
            TextField("Status", text: $store.status)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ValueStore())
}
