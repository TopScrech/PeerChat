import SwiftUI
import Observation
#if canImport(DeviceKit)
import DeviceKit
#endif

@Observable
final class ValueStore {
    private let defaults = UserDefaults.standard

    var nickname: String {
        get { defaults.string(forKey: "nickname") ?? ValueStore.defaultNickname }
        set { defaults.set(newValue, forKey: "nickname") }
    }

    var status: String {
        get { defaults.string(forKey: "status") ?? "" }
        set { defaults.set(newValue, forKey: "status") }
    }
    
    var deviceID: UUID {
        if let storedDeviceID = defaults.string(forKey: "deviceID"),
           let existingID = UUID(uuidString: storedDeviceID) {
            return existingID
        }
        
        let newID = ValueStore.defaultDeviceID
        defaults.set(newID.uuidString, forKey: "deviceID")
        
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
