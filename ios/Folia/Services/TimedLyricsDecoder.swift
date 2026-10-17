import Foundation
import JavaScriptCore
import zlib
// ios/Folia/Services/TimedLyricsDecoder.swift

enum TimedLyricsDecoder {
    static func krc(_ encoded: String) throws -> String {
        guard let bytes = Data(base64Encoded: encoded), bytes.count > 4, bytes.starts(with: Array("krc1".utf8)) else { throw MusicError.invalidResponse }
        let key: [UInt8] = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
        let compressed = Data(bytes.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % 16] })
        return try inflate(compressed)
    }
    static func qrc(_ hex: String) throws -> String {
        let chars = Array(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !chars.isEmpty, chars.count % 2 == 0 else { throw MusicError.invalidResponse }
        var input: [UInt8] = []
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { throw MusicError.invalidResponse }
            input.append(byte)
        }
        // The original custom DES substitutions are reused byte-for-byte; no audio or UI runs in JavaScriptCore.
        guard let context = JSContext() else { throw MusicError.invalidResponse }
        context.evaluateScript(QRCAlgorithm.script)
        guard context.exception == nil,
              let result = context.objectForKeyedSubscript("decryptArray")?.call(withArguments: [input])?.toArray() as? [NSNumber],
              context.exception == nil else { throw MusicError.invalidResponse }
        return try inflate(Data(result.map(\.uint8Value)))
    }
    static func inflate(_ input: Data) throws -> String {
        guard !input.isEmpty, input.count < 4 * 1024 * 1024 else { throw MusicError.invalidResponse }
        var capacity = max(4096, input.count * 4)
        // Bound decoded lyrics to 8 MiB to avoid unbounded decompression from a malformed upstream payload.
        while capacity <= 8 * 1024 * 1024 {
            var output = [UInt8](repeating: 0, count: capacity)
            var count = uLongf(capacity)
            let result = input.withUnsafeBytes { bytes in
                uncompress(&output, &count, bytes.bindMemory(to: UInt8.self).baseAddress!, uLong(input.count))
            }
            if result == Z_OK { return String(decoding: output.prefix(Int(count)), as: UTF8.self) }
            guard result == Z_BUF_ERROR else { throw MusicError.invalidResponse }
            capacity *= 2
        }
        throw MusicError.invalidResponse
    }
}
