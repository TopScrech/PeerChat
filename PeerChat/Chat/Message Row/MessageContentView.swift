import ScrechKit
import SwiftoCrypto

struct MessageContentView: View {
    @Environment(CryptoModel.self) private var crypto
    
    let message: Message
    let isCurrentUser: Bool
    var canDelete = false
    var onDelete: (() -> Void)?
    
    var body: some View {
        switch message.contentType {
        case .text:
            if let decryptedText {
                if !decryptedText.trimmingCharacters(in: .whitespacesAndNewlines).containsOnlyEmoji {
                    Text(decryptedText)
                        .foregroundStyle(isCurrentUser ? .white : .primary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(
                            isCurrentUser ? .blue : .secondary,
                            in: .rect(cornerRadius: 20, style: .continuous)
                        )
                } else {
                    Text(decryptedText.trimmingCharacters(in: .whitespacesAndNewlines))
                        .largeTitle()
                        .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                        .padding()
                }
            }
        case .voice:
            VoiceMessageBubble(
                audioData: decryptedAttachmentData,
                duration: message.voiceDuration,
                isCurrentUser: isCurrentUser
            )
        case .file:
            FileMessageBubble(
                fileName: message.attachmentName,
                fileData: decryptedAttachmentData,
                isCurrentUser: isCurrentUser,
                canDelete: canDelete,
                onDelete: onDelete
            )
        }
    }
    
    private var decryptedText: String? {
        guard let encryptedData = Data(base64Encoded: message.text) else {
            print("Invalid encrypted text")
            return nil
        }
        
        return crypto.decrypt(encryptedData, using: crypto.privateKey)
    }
    
    private var decryptedAttachmentData: Data? {
        guard let encryptedAttachment = message.attachmentData else {
            return nil
        }
        
        if let attachmentData = crypto.decryptAttachment(encryptedAttachment) {
            return attachmentData
        }
        
        guard let legacyAttachmentString = crypto.decrypt(encryptedAttachment, using: crypto.privateKey) else {
            return nil
        }
        
        return Data(base64Encoded: legacyAttachmentString)
    }
}
