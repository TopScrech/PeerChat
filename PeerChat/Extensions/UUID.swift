import Foundation

extension UUID {
    var firstThreeNumbers: String? {
        let uuidStr = self.uuidString
        
        if let firstThreeNumbersRange = uuidStr.range(of: "\\d{3}", options: .regularExpression) {
            return String(uuidStr[firstThreeNumbersRange])
        }
        
        return nil
    }
}
