import Foundation
import Security

enum PeerTLSIdentity {
    static func make() -> sec_identity_t? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ]
        var keyError: Unmanaged<CFError>?

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &keyError) else {
            return nil
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }

        var publicKeyError: Unmanaged<CFError>?

        guard let publicKeyData = SecKeyCopyExternalRepresentation(
            publicKey,
            &publicKeyError
        ) as Data? else {
            return nil
        }

        let signatureAlgorithm = sequence(
            objectIdentifier([1, 2, 840, 10045, 4, 3, 2])
        )
        let commonName = sequence(
            objectIdentifier([2, 5, 4, 3]) + utf8String("PeerChat")
        )
        let distinguishedName = sequence(set(commonName))
        let validity = sequence(
            utcTime(Date().addingTimeInterval(-60)) +
            utcTime(Date().addingTimeInterval(31_536_000))
        )
        let publicKeyAlgorithm = sequence(
            objectIdentifier([1, 2, 840, 10045, 2, 1]) +
            objectIdentifier([1, 2, 840, 10045, 3, 1, 7])
        )
        let subjectPublicKeyInfo = sequence(
            publicKeyAlgorithm + bitString(publicKeyData)
        )
        var serialUUID = UUID().uuid
        let serial = withUnsafeBytes(of: &serialUUID) { Data($0) }
        let version = tagged(0xA0, integer(Data([2])))
        let certificateBody = sequence(
            version +
            integer(serial) +
            signatureAlgorithm +
            distinguishedName +
            validity +
            distinguishedName +
            subjectPublicKeyInfo
        )
        var signatureError: Unmanaged<CFError>?

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            certificateBody as CFData,
            &signatureError
        ) as Data? else {
            return nil
        }

        let certificateData = sequence(
            certificateBody + signatureAlgorithm + bitString(signature)
        )

        guard let certificate = SecCertificateCreateWithData(
            nil,
            certificateData as CFData
        ) else {
            return nil
        }

        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            return nil
        }

        return sec_identity_create(identity)
    }

    private static func tagged(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + encodedLength(content.count) + content
    }

    private static func sequence(_ content: Data) -> Data {
        tagged(0x30, content)
    }

    private static func set(_ content: Data) -> Data {
        tagged(0x31, content)
    }

    private static func integer(_ value: Data) -> Data {
        var normalized = value.drop(while: { $0 == 0 })

        if normalized.isEmpty {
            normalized = Data([0])[...]
        }

        var content = Data(normalized)

        if let first = content.first, first & 0x80 != 0 {
            content.insert(0, at: 0)
        }

        return tagged(0x02, content)
    }

    private static func bitString(_ value: Data) -> Data {
        tagged(0x03, Data([0]) + value)
    }

    private static func utf8String(_ value: String) -> Data {
        tagged(0x0C, Data(value.utf8))
    }

    private static func utcTime(_ date: Date) -> Data {
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0) ?? .current,
            from: date
        )
        let value = twoDigits((components.year ?? 2000) % 100) +
            twoDigits(components.month ?? 1) +
            twoDigits(components.day ?? 1) +
            twoDigits(components.hour ?? 0) +
            twoDigits(components.minute ?? 0) +
            twoDigits(components.second ?? 0) +
            "Z"

        return tagged(0x17, Data(value.utf8))
    }

    private static func twoDigits(_ value: Int) -> String {
        let digits = String(value)
        return digits.count == 1 ? "0" + digits : digits
    }

    private static func objectIdentifier(_ components: [UInt64]) -> Data {
        guard components.count >= 2 else {
            return tagged(0x06, Data())
        }

        var content = Data()
        content.append(UInt8(components[0] * 40 + components[1]))

        for component in components.dropFirst(2) {
            var encoded = [UInt8(component & 0x7F)]
            var remaining = component >> 7

            while remaining > 0 {
                encoded.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
                remaining >>= 7
            }

            content.append(contentsOf: encoded)
        }

        return tagged(0x06, content)
    }

    private static func encodedLength(_ length: Int) -> Data {
        guard length >= 128 else {
            return Data([UInt8(length)])
        }

        var remaining = length
        var bytes: [UInt8] = []

        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }

        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
