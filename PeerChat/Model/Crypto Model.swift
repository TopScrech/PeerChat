import Foundation
import CryptoKit

@Observable
final class CryptoModel {
    let privateKey = P521.KeyAgreement.PrivateKey()
    
    var publicKey: P521.KeyAgreement.PublicKey {
        privateKey.publicKey
    }
    
    var receivedPublicKey: P521.KeyAgreement.PublicKey?
    
    func sharedSymmetricKey(
        privateKey: P521.KeyAgreement.PrivateKey,
        publicKey: P521.KeyAgreement.PublicKey
    ) -> SymmetricKey {
        
        let sharedSecret = try! privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        return symmetricKey
    }
    
    func encrypt(
        _ text: String,
        using publicKey: P521.KeyAgreement.PublicKey
    ) -> Data? {
        
        guard
            let data = text.data(using: .utf8),
            let encryptedData = try? ChaChaPoly
                .seal(data, using: sharedSymmetricKey(privateKey: privateKey, publicKey: publicKey))
                .combined
        else {
            print("Encryption failed")
            return nil
        }
        
        return encryptedData
    }
    
    func decrypt(
        _ data: Data,
        using privateKey: P521.KeyAgreement.PrivateKey
    ) -> String? {
        
        guard
            let publicKey = receivedPublicKey,
            let box = try? ChaChaPoly.SealedBox(combined: data),
            let decryptedData = try? ChaChaPoly.open(box, using: sharedSymmetricKey(privateKey: privateKey, publicKey: publicKey)),
            let decryptedText = String(data: decryptedData, encoding: .utf8)
        else {
            print("Decryption failed")
            return nil
        }
        
        return decryptedText
    }
}
