import SwiftUI
import QuickLooking

struct FileMessageBubble: View {
    let fileName: String?
    let fileData: Data?
    let isCurrentUser: Bool
    
    @State private var previewItem: QuickLookPreview?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(fileName ?? "File", systemImage: "doc.fill")
                .callout(.semibold)
            
            if let fileData {
                Text(ByteCountFormatStyle().format(Int64(fileData.count)))
                    .caption()
                    .foregroundStyle(isCurrentUser ? .white.opacity(0.9) : .secondary)
                
                HStack(spacing: 12) {
                    Button("Open", systemImage: "doc.text.magnifyingglass", action: openPreview)
                    
                    ShareLink(item: fileData, preview: SharePreview(fileName ?? "File")) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .callout()
                .foregroundStyle(isCurrentUser ? .white : .blue)
            } else {
                Text("File unavailable")
                    .callout()
                    .foregroundStyle(isCurrentUser ? .white.opacity(0.9) : .secondary)
            }
        }
        .foregroundStyle(isCurrentUser ? .white : .primary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            isCurrentUser ? .blue : .secondary,
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .sheet(
            item: $previewItem,
            onDismiss: cleanupPreviewFile
        ) {
            QuickLookView($0.url)
        }
    }
    
    private func openPreview() {
        guard let fileData else {
            return
        }
        
        let previewDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("PeerChatQuickLook", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(
                at: previewDirectory,
                withIntermediateDirectories: true
            )
            
            let previewName = "\(UUID().uuidString)-\(sanitizedFileName)"
            let url = previewDirectory.appendingPathComponent(previewName)
            
            try fileData.write(to: url, options: .atomic)
            previewItem = .init(url: url)
        } catch {
            print("Could not prepare Quick Look preview")
        }
    }
    
    private func cleanupPreviewFile() {
        guard let previewItem else {
            return
        }
        
        try? FileManager.default.removeItem(at: previewItem.url)
        self.previewItem = nil
    }
    
    private var sanitizedFileName: String {
        let defaultName = fileName ?? "File"
        
        return defaultName.replacingOccurrences(
            of: "/",
            with: "-"
        )
    }
}

private struct QuickLookPreview: Identifiable {
    let url: URL
    
    var id: URL { url }
}
