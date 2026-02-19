import Foundation

struct PreparedAttachmentFile {
    let directoryURL: URL
    let url: URL
    let fileName: String
    
    static func make(fileName: String?, fileData: Data?) -> PreparedAttachmentFile? {
        guard let fileData else {
            return nil
        }
        
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("PeerChatAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        let safeFileName = sanitize(fileName)
        let fileURL = directory.appendingPathComponent(safeFileName)
        
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try fileData.write(to: fileURL, options: .atomic)
            
            return .init(
                directoryURL: directory,
                url: fileURL,
                fileName: safeFileName
            )
        } catch {
            print("Could not prepare file")
            return nil
        }
    }
    
    static func sanitize(_ fileName: String?) -> String {
        let defaultName = fileName ?? "File"
        
        return defaultName.replacingOccurrences(
            of: "/",
            with: "-"
        )
    }
}
