import SwiftUI
import ScrechKit
#if os(macOS)
import AppKit
#else
import QuickLooking
#endif

struct FileMessageBubble: View {
    let fileName: String?
    let fileData: Data?
    let isCurrentUser: Bool
    
    @State private var preparedFile: PreparedFile?
    @State private var openedFileURL: URL?
#if !os(macOS)
    @State private var previewItem: QuickLookPreview?
#endif
    
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
                    
                    if let preparedFile {
                        ShareLink(
                            item: preparedFile.url,
                            preview: SharePreview(preparedFile.fileName)
                        ) {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    } else {
                        Button("Save", systemImage: "square.and.arrow.down") {}
                            .disabled(true)
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
        .task(id: fileIdentity) {
            prepareFile()
        }
        .onDisappear(perform: cleanupPreparedFile)
#if !os(macOS)
        .sheet(
            item: $previewItem
        ) { preview in
            NavigationStack {
                QuickLookView(preview.url)
                    .navigationTitle(preview.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
#endif
    }
    
    private func openPreview() {
        if preparedFile == nil {
            preparedFile = makePreparedFile()
        }
        
        guard let preparedFile else {
            return
        }
        
#if os(macOS)
        openedFileURL = preparedFile.url
        NSWorkspace.shared.open(preparedFile.url)
#else
        previewItem = .init(
            url: preparedFile.url,
            title: preparedFile.fileName
        )
#endif
    }
    
    private func prepareFile() {
        guard preparedFile == nil else {
            return
        }
        
        preparedFile = makePreparedFile()
    }
    
    private func makePreparedFile() -> PreparedFile? {
        guard let fileData else {
            return nil
        }
        
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("PeerChatAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        let fileName = sanitizedFileName
        let fileURL = directory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try fileData.write(to: fileURL, options: .atomic)
            
            return .init(
                directoryURL: directory,
                url: fileURL,
                fileName: fileName
            )
        } catch {
            print("Could not prepare file")
            return nil
        }
    }
    
    private func cleanupPreparedFile() {
        guard let preparedFile else {
            cleanupPreviewState()
            return
        }
        
        try? FileManager.default.removeItem(at: preparedFile.directoryURL)
        self.preparedFile = nil
        cleanupPreviewState()
    }
    
    private func cleanupPreviewState() {
#if os(macOS)
        self.openedFileURL = nil
#else
        self.previewItem = nil
#endif
    }
    
    private var fileIdentity: String {
        "\(sanitizedFileName)-\(fileData?.count ?? -1)"
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
    let title: String
    
    var id: URL { url }
}

private struct PreparedFile {
    let directoryURL: URL
    let url: URL
    let fileName: String
}
