#if os(iOS)
import AVKit
import SwiftUI

struct AudioRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.activeTintColor = UIColor.label
        picker.tintColor = UIColor.label
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
import SwiftUI

struct AudioRoutePickerView: View {
    var body: some View {
        Image(systemName: "airplayaudio")
    }
}
#endif

