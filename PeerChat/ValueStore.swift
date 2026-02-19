import SwiftUI
import DeviceKit
import Combine
#if canImport(UIKit)
import UIKit
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
    
    private static var defaultNickname: String {
        if let name = Device.current.name, !name.isEmpty {
            return name
        }
        
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
