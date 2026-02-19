import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ValueStore
    
    var body: some View {
        List {
            TextField("Nickname", text: $store.nickname)
            Button("Reset Name", systemImage: "arrow.counterclockwise", action: store.resetNickname)
            TextField("Status", text: $store.status)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ValueStore())
}
