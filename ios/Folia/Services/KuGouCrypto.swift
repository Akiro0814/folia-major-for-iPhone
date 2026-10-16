import Foundation
import Security
import CommonCrypto
// ios/Folia/Services/KuGouCrypto.swift

enum KuGouCrypto {
    static func encrypt(_ body: [String: Any], time: Int64) throws -> (cipher: String, pk: String, key: String) {
        let key = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        let aesKey = ProtocolCrypto.md5(key)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
        let cipher = try ProtocolCrypto.aes(json, key: aesKey, iv: String(aesKey.suffix(16))).map { String(format: "%02x", $0) }.joined()
        let pkJSON = try JSONSerialization.data(withJSONObject: ["clienttime_ms": time, "key": key], options: [.sortedKeys])
        let spki = Data(base64Encoded: "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB")!
        guard let rsa = SecKeyCreateWithData(spki.dropFirst(22) as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: 1024] as CFDictionary, nil), pkJSON.count <= 128 else { throw MusicError.invalidResponse }
        var padded = pkJSON
        padded.append(Data(repeating: 0, count: 128 - pkJSON.count))
        guard let encrypted = SecKeyCreateEncryptedData(rsa, .rsaEncryptionRaw, padded as CFData, nil) as Data? else { throw MusicError.invalidResponse }
        return (cipher, encrypted.map { String(format: "%02X", $0) }.joined(), key)
    }
    static func decrypt(_ hex: String, key: String) throws -> Data {
        let characters = Array(hex)
        guard characters.count % 2 == 0 else { throw MusicError.invalidResponse }
        var input: [UInt8] = []
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let value = UInt8(String(characters[index...index + 1]), radix: 16) else { throw MusicError.invalidResponse }
            input.append(value)
        }
        let secret = Array(ProtocolCrypto.md5(key).utf8)
        let vector = Array(secret.suffix(16))
        var output = [UInt8](repeating: 0, count: input.count + 16)
        var written = 0
        let capacity = output.count
        let status = input.withUnsafeBytes { data in secret.withUnsafeBytes { key in vector.withUnsafeBytes { iv in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                key.baseAddress, secret.count, iv.baseAddress, data.baseAddress, input.count, &output, capacity, &written)
        } } }
        guard status == kCCSuccess else { throw MusicError.invalidResponse }
        return Data(output.prefix(written))
    }
}
