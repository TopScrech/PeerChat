import SwiftUI

final class ValueStore: ObservableObject {
    @AppStorage("nickname") var nickname = UIDevice.current.model
    @AppStorage("status") var status = ""
}
