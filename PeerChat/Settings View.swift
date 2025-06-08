import SwiftUI

struct SettingsView: View {
    @AppStorage("nickname") var nickname = UIDevice.current.model
    @AppStorage("status") var status = ""
    
    var body: some View {
        List {
            TextField("Nickname", text: $nickname)
            
            TextField("Status", text: $status)
        }
    }
}

#Preview {
    SettingsView()
}
