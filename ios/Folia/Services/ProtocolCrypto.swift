import Foundation
import CommonCrypto
import Security
// ios/Folia/Services/ProtocolCrypto.swift

enum ProtocolCrypto {
    static func md5(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        bytes.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(bytes.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    static func aes(_ text: String, key: String, iv: String? = nil) throws -> Data {
        let input = Array(text.utf8), secret = Array(key.utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let options = CCOptions(kCCOptionPKCS7Padding | (iv == nil ? kCCOptionECBMode : 0))
        let vector = iv.map { Array($0.utf8) } ?? [UInt8](repeating: 0, count: 16)
        let capacity = output.count
        let status = input.withUnsafeBytes { source in
            secret.withUnsafeBytes { secretBuffer in
                vector.withUnsafeBytes { ivBuffer in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options,
                            secretBuffer.baseAddress, secret.count, ivBuffer.baseAddress,
                            source.baseAddress, input.count, &output, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw MusicError.invalidResponse }
        return Data(output.prefix(written))
    }
    static func eapi(path: String, json: String) throws -> String {
        let digest = md5("nobody\(path)use\(json)md5forencrypt")
        return try aes("\(path)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)", key: "e82ckenh8dichen8")
            .map { String(format: "%02X", $0) }.joined()
    }
    // Port of api-enhanced 4.41.1 weapi: two AES-CBC passes and unpadded RSA.
    static func weapi(_ body: [String: Any]) throws -> [String: String] {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let secret = String((0..<16).map { _ in alphabet.randomElement()! })
        let first = try aes(json, key: "0CoJUm6Qyw8W8jud", iv: "0102030405060708").base64EncodedString()
        let encrypted = try aes(first, key: secret, iv: "0102030405060708").base64EncodedString()
        let spki = Data(base64Encoded: "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB")!
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits as String: 1024]
        guard let key = SecKeyCreateWithData(spki.dropFirst(22) as CFData, attributes as CFDictionary, nil) else {
            throw MusicError.invalidResponse
        }
        var padded = Data(repeating: 0, count: 112)
        padded.append(contentsOf: secret.utf8.reversed())
        guard let rsa = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, padded as CFData, nil) as Data? else {
            throw MusicError.invalidResponse
        }
        return ["params": encrypted, "encSecKey": rsa.map { String(format: "%02x", $0) }.joined()]
    }
}

