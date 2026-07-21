import SwiftUI

struct SettingsView: View {
    @Environment(ValueStore.self) private var store
    
    var body: some View {
        @Bindable var store = store

        List {
            TextField("Nickname", text: $store.nickname)
            Button("Reset Name", systemImage: "arrow.counterclockwise", action: store.resetNickname)
            TextField("Status", text: $store.status)
        }
    }
}

#Preview {
    SettingsView()
        .environment(ValueStore())
}
