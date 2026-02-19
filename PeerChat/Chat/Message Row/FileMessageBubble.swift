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
    var canDelete = false
    var onDelete: (() -> Void)?
    
    @State private var preparedFile: PreparedAttachmentFile?
#if !os(macOS)
    @State private var previewItem: QuickLookPreview?
#endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(fileName ?? "File", systemImage: "doc.fill")
                .callout(.semibold)

            if fileData == nil {
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
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            openPreview()
        }
        .preference(
            key: FileMessagePreparedFilePreferenceKey.self,
            value: preparedFile.map {
                .init(
                    url: $0.url,
                    fileName: $0.fileName
                )
            }
        )
        .task(id: fileIdentity) {
            prepareFile()
        }
        .onDisappear(perform: cleanupPreparedFile)
#if !os(macOS)
        .sheet(item: $previewItem) { preview in
            NavigationStack {
                QuickLookView(preview.url)
                    .navigationTitle(preview.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if let preparedFile {
                            ShareLink(
                                item: preparedFile.url,
                                preview: SharePreview(preparedFile.fileName)
                            ) {
                                Label("Save", systemImage: "square.and.arrow.up")
                            }
                        }

                        if canDelete, let onDelete {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                previewItem = nil
                                onDelete()
                            }
                        }
                    }
            }
        }
#endif
    }
    
    private func openPreview() {
        if preparedFile == nil {
            prepareFile()
        }
        
        guard let preparedFile else {
            return
        }
        
#if os(macOS)
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
        
        preparedFile = PreparedAttachmentFile.make(
            fileName: fileName,
            fileData: fileData
        )
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
#if !os(macOS)
        self.previewItem = nil
#endif
    }
    
    private var fileIdentity: String {
        "\(PreparedAttachmentFile.sanitize(fileName))-\(fileData?.count ?? -1)"
    }
}

private struct QuickLookPreview: Identifiable {
    let url: URL
    let title: String
    
    var id: URL { url }
}
