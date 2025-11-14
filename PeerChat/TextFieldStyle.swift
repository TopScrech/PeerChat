import SwiftUI

struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(10)
            .background(.ultraThickMaterial)
            .cornerRadius(8)
            .foregroundColor(.primary)
    }
}
