import SwiftUI

struct FileMessagePreparedFileContext: Equatable {
    let url: URL
    let fileName: String
}

struct FileMessagePreparedFilePreferenceKey: PreferenceKey {
    static var defaultValue: FileMessagePreparedFileContext?
    
    static func reduce(
        value: inout FileMessagePreparedFileContext?,
        nextValue: () -> FileMessagePreparedFileContext?
    ) {
        value = nextValue()
    }
}
