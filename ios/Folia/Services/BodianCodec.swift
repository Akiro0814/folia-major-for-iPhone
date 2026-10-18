import Foundation
import CoreFoundation
// ios/Folia/Services/BodianCodec.swift

extension BodianProvider {
    static func number(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        return (value as? String).flatMap(Int.init)
    }
    static func queryString(_ fields: [(String, String)]) -> String {
        func encode(_ text: String) -> String {
            text.utf8.map { byte -> String in
                if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [42, 45, 46, 95].contains(byte) { return String(UnicodeScalar(byte)) }
                return byte == 32 ? "+" : String(format: "%%%02X", byte)
            }.joined()
        }
        return fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&")
    }
    static func signature(path: String, fields: [(String, String)], body: String = "") -> String {
        let letters = queryString(fields).utf8.filter { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }.sorted()
        var seed = "kuwotest" + String(decoding: letters, as: UTF8.self)
        if !body.isEmpty { seed += ProtocolCrypto.md5(body + "kuwotest") }
        return ProtocolCrypto.md5(seed + path)
    }
    static func mediaID(_ id: String) throws -> Int64 {
        guard (1...20).contains(id.count), id.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int64(id), value > 0, value <= 9_007_199_254_740_991 else { throw MusicError.invalidResponse }
        return value
    }
    static func validateRights(_ rights: [String: Any]) throws {
        guard let status = number(rights["status"]) else { throw MusicError.unavailable("波点音乐未提供播放权限。") }
        guard status != 3 else { throw MusicError.unavailable("波点仅提供试听片段，请使用具有完整歌曲播放权益的账号。") }
        guard status != 7 else { throw MusicError.unavailable("波点音乐要求额外播放授权。") }
    }
    static func loginAccount(_ login: [String: Any]) throws -> MusicAccount {
        let user = login["userInfo"] as? [String: Any] ?? login["user"] as? [String: Any] ?? [:]
        let rawIdentities = [login["id"], login["uid"], user["id"], user["uid"]].compactMap { $0 }
        guard rawIdentities.allSatisfy({ value in
            guard let number = value as? NSNumber else { return value is String }
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return number.doubleValue.isFinite && number.doubleValue.rounded() == number.doubleValue && number.doubleValue <= 9_007_199_254_740_991
        }) else { throw MusicError.invalidResponse }
        let identities = rawIdentities.compactMap(OmniService.identifier)
        guard let id = identities.first, (1...20).contains(id.count), id.first != "0", id.allSatisfy({ $0.isASCII && $0.isNumber }), identities.allSatisfy({ $0 == id }),
              let token = login["token"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MusicError.invalidResponse }
        return MusicAccount(id: id, provider: .bodian, nickname: user["nickname"] as? String ?? "波点用户",
                            avatarURL: (user["headImg"] as? String ?? user["avatarUrl"] as? String).flatMap(URL.init(string:)))
    }
    static func normalize(_ item: [String: Any]) -> Track? {
        guard let id = OmniService.identifier(item["id"]), (try? mediaID(id)) != nil else { return nil }
        let artists = item["artists"] as? [[String: Any]] ?? []
        let artist = artists.isEmpty ? (item["artist"] as? String ?? "") : artists.compactMap { $0["name"] as? String }.joined(separator: " / ")
        var metadata: [String: String] = [:]
        for key in ["freeSign", "albumId", "artistId"] { if let value = OmniService.identifier(item[key]) { metadata[key] = value } }
        if metadata["freeSign"] == nil { metadata["freeSign"] = item["fsig"] as? String }
        return Track(mediaID: id, provider: .bodian, title: item["songName"] as? String ?? item["name"] as? String ?? "", artist: artist,
                     album: item["album"] as? String ?? "", artworkURL: coverURL(item["albumPic"]),
                     duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0, providerData: metadata)
    }
    static func collection(_ item: [String: Any], owned: Bool = false) -> MusicCollection? {
        guard let id = OmniService.identifier(item["id"]), (try? mediaID(id)) != nil else { return nil }
        return MusicCollection(id: id, provider: .bodian, title: item["name"] as? String ?? "",
            artworkURL: coverURL(item["pic"]), trackCount: number(item["musicCount"]) ?? number(item["musicCnt"]) ?? 0,
            providerData: ["source": String(number(item["sourceType"]) ?? (owned ? 5 : 4))])
    }
    static func coverURL(_ value: Any?) -> URL? {
        guard var text = value as? String else { return nil }
        if text.hasPrefix("http://"), let host = URL(string: text)?.host, host.split(separator: ".").count == 3, host.hasSuffix(".kuwo.cn") {
            text = "https://" + text.dropFirst(7)
        }
        return URL(string: text)
    }
    // Port of bodian-music-api 0.1.2: each lyric file carries octal obfuscation factors.
    static func decodeLyrics(_ text: String) -> LyricsPayload {
        let timing = try! NSRegularExpression(pattern: "<(-?\\d+),(-?\\d+)>")
        let tag = try! NSRegularExpression(pattern: "\\[kuwo:([^\\]]*)\\]")
        let source = text as NSString
        let tagMatch = tag.firstMatch(in: text, range: NSRange(location: 0, length: source.length))
        let factor = tagMatch.flatMap { Int(source.substring(with: $0.range(at: 1)), radix: 8) } ?? 11
        let untimed = timing.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: source.length), withTemplate: "")
        let plain = tag.stringByReplacingMatches(in: untimed, range: NSRange(location: 0, length: (untimed as NSString).length), withTemplate: "")
        guard factor / 10 > 0, factor % 10 > 0 else { return LyricsPayload(original: plain) }
        var decoded = text
        for match in timing.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let a = Double(source.substring(with: match.range(at: 1))), let b = Double(source.substring(with: match.range(at: 2))), let range = Range(match.range, in: decoded) else { continue }
            let rawStart = abs((a + b) / Double(2 * (factor / 10)))
            let rawDuration = abs((a - b) / Double(2 * (factor % 10)))
            guard rawStart.isFinite, rawDuration.isFinite, rawStart < Double(Int.max), rawDuration < Double(Int.max) else { continue }
            let start = Int(rawStart)
            let duration = Int(rawDuration)
            decoded.replaceSubrange(range, with: "<\(start),\(duration)>")
        }
        decoded = tag.stringByReplacingMatches(in: decoded, range: NSRange(location: 0, length: (decoded as NSString).length), withTemplate: "")
        return LyricsPayload(original: plain, wordTimed: timing.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) == nil ? "" : decoded)
    }
}
