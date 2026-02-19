import Foundation
import CryptoKit
import SwiftoCrypto

extension CryptoModel {
    func encryptAttachment(_ data: Data) -> Data? {
        guard let symmetricKey = attachmentSymmetricKey else {
            print("Missing peer public key")
            return nil
        }
        
        do {
            let sealedBox = try ChaChaPoly.seal(
                data,
                using: symmetricKey
            )
            
            return sealedBox.combined
        } catch {
            print("Attachment encryption failed")
            return nil
        }
    }
    
    func decryptAttachment(_ data: Data) -> Data? {
        guard let symmetricKey = attachmentSymmetricKey else {
            print("Missing peer public key")
            return nil
        }
        
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: data)
            
            return try ChaChaPoly.open(
                sealedBox,
                using: symmetricKey
            )
        } catch {
            print("Attachment decryption failed")
            return nil
        }
    }
    
    private var attachmentSymmetricKey: SymmetricKey? {
        guard let receivedPublicKey else {
            return nil
        }
        
        guard let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: receivedPublicKey) else {
            return nil
        }
        
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
}
