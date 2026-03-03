import SwiftUI
#if canImport(DeviceKit)
import DeviceKit
#endif

final class ValueStore: ObservableObject {
    @AppStorage("nickname") var nickname = ValueStore.defaultNickname
    @AppStorage("status") var status = ""
    @AppStorage("deviceID") private var storedDeviceID = ""
    
    var deviceID: UUID {
        if let existingID = UUID(uuidString: storedDeviceID) {
            return existingID
        }
        
        let newID = ValueStore.defaultDeviceID
        storedDeviceID = newID.uuidString
        
        return newID
    }
    
    func resetNickname() {
        nickname = ValueStore.defaultNickname
    }
    
    private static var defaultNickname: String {
#if canImport(DeviceKit)
        let name = Device.current.description
        
        if !name.isEmpty {
            return name
        }
#endif
#if os(iOS)
        return UIDevice.current.model
#elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
#else
        return "Device"
#endif
    }
    
    private static var defaultDeviceID: UUID {
#if os(iOS)
        return UIDevice.current.identifierForVendor ?? UUID()
#else
        return UUID()
#endif
    }
}
