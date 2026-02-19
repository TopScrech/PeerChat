import SwiftUI
import QuickLooking

struct FileMessageBubble: View {
    let fileName: String?
    let fileData: Data?
    let isCurrentUser: Bool
    
    @State private var isShowingPreview = false
    @State private var previewFileURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(fileName ?? "File", systemImage: "doc.fill")
                .font(.callout.weight(.semibold))
            
            if let fileData {
                Text(ByteCountFormatStyle().format(Int64(fileData.count)))
                    .font(.caption)
                    .foregroundStyle(isCurrentUser ? .white.opacity(0.9) : .secondary)
                
                HStack(spacing: 12) {
                    Button("Open", systemImage: "doc.text.magnifyingglass", action: openPreview)
                    
                    ShareLink(
                        item: fileData,
                        preview: SharePreview(fileName ?? "File")
                    ) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.callout)
                .foregroundStyle(isCurrentUser ? .white : .blue)
            } else {
                Text("File unavailable")
                    .font(.caption)
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
            isPresented: $isShowingPreview,
            onDismiss: cleanupPreviewFile
        ) {
            if let previewFileURL {
                QuickLookView(previewFileURL)
            } else {
                Text("Preview unavailable")
            }
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
            previewFileURL = url
            isShowingPreview = true
        } catch {
            print("Could not prepare Quick Look preview")
        }
    }
    
    private func cleanupPreviewFile() {
        guard let previewFileURL else {
            return
        }
        
        try? FileManager.default.removeItem(at: previewFileURL)
        self.previewFileURL = nil
    }
    
    private var sanitizedFileName: String {
        let defaultName = fileName ?? "File"
        
        return defaultName.replacingOccurrences(
            of: "/",
            with: "-"
        )
    }
}
