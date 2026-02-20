import SwiftUI

struct InCallControlsView: View {
    @Environment(Model.self) private var model

    private var callStatusText: String {
        switch model.callState {
        case .dialing:
            "Dialing \(model.callDisplayName)"
        case .ringing:
            "Ringing \(model.callDisplayName)"
        case .active:
            "In call with \(model.callDisplayName)"
        case .idle:
            ""
        }
    }

    private var muteIcon: String {
        if model.isMicrophoneMuted {
            "mic.slash.fill"
        } else {
            "mic.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(callStatusText, systemImage: "phone.fill")
                .lineLimit(1)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            AudioRoutePickerView()
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: .circle)

            Button("", systemImage: muteIcon) {
                model.toggleMicrophoneMuted()
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(model.isMicrophoneMuted ? .yellow : .primary)
            .background(.thinMaterial, in: .circle)

            Button("", systemImage: "phone.down.fill", role: .destructive) {
                model.endCall()
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(.white)
            .background(.red, in: .circle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
