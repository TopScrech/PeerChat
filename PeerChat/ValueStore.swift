import SwiftUI
import DeviceKit

final class ValueStore: ObservableObject {
    @AppStorage("nickname") var nickname = Device.current.name ?? UIDevice.current.model
    @AppStorage("status") var status = ""
}
