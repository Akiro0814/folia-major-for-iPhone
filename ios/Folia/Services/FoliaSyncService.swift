import Foundation
import Security
// ios/Folia/Services/FoliaSyncService.swift

/// Manual cross-platform settings synchronization using the existing Folia sync-server contract.
actor FoliaSyncService {
    private let session: URLSession
    init(session: URLSession? = nil) {
        let network = URLSessionConfiguration.ephemeral
        network.httpShouldSetCookies = false; network.urlCache = nil
        self.session = session ?? URLSession(configuration: network)
    }

    func download(server: String, token: String, existing: VisualSettings) async throws -> VisualSettings? {
        guard let record = try await read(server: server, token: token) else { return nil }
        return try Self.visualSettings(record, existing: existing)
    }
    // Read-modify-write keeps desktop-only settings intact; this server uses timestamp-based last-write-wins.
    func upload(_ settings: VisualSettings, server: String, token: String) async throws {
        let existing = try await read(server: server, token: token)
        let record = try Self.merge(settings, into: existing)
        _ = try await request(server: server, token: token, method: "PUT", body: JSONSerialization.data(withJSONObject: record))
        let confirmed = try await read(server: server, token: token)
        guard confirmed?["updatedAt"] as? String == record["updatedAt"] as? String else {
            throw MusicError.unavailable("服务器保留了更新的配置，请先下载后重试上传。")
        }
    }
    private func read(server: String, token: String) async throws -> [String: Any]? {
        let data = try await request(server: server, token: token, method: "GET")
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if root is NSNull { return nil }
        guard let record = root as? [String: Any] else { throw MusicError.invalidResponse }
        try Self.validate(record)
        return record
    }
    private func request(server: String, token: String, method: String, body: Data? = nil) async throws -> Data {
        guard var parts = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { throw MusicError.unavailable("请输入有效的同步服务器 HTTP(S) 地址。") }
        guard token.count >= 8 else { throw MusicError.unavailable("同步令牌至少需要 8 个字符。") }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = (parts.path.isEmpty ? "" : "/" + parts.path) + "/settings"
        guard let url = parts.url else { throw MusicError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MusicError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MusicError.server(http.statusCode, "同步服务器请求失败") }
        guard data.count < 4_000_000 else { throw MusicError.unavailable("同步设置过大。") }
        return data
    }
    // Introducing the modern bundle disables ALL legacy tuning keys on desktop, so migrate every legacy mode first.
    private static func tuningBundle(_ data: [String: Any]) -> [String: Any] {
        let modes = ["classic", "cadenza", "partita", "fume", "claddagh", "cappella", "tilt", "diorama", "monet", "pendolo", "sonnet", "tempera", "lumiere"]
        var bundle = data["visualizerTunings"] as? [String: Any] ?? [:]
        if data["visualizerTunings"] == nil {
            for mode in modes { if let value = data[mode + "Tuning"] as? [String: Any] { bundle[mode] = value } }
        }
        for mode in ["monet", "nomand", "latent", "sora"] {
            if let value = data[mode + "BackgroundTuning"] as? [String: Any] { bundle[mode + "_background"] = value }
        }
        return bundle
    }
    private static func mergeObjects(_ updates: [String: Any], into existing: [String: Any]) -> [String: Any] {
        var result = existing
        for (key, value) in updates {
            if let object = value as? [String: Any], let original = existing[key] as? [String: Any] { result[key] = mergeObjects(object, into: original) }
            else { result[key] = value }
        }
        return result
    }
    private static func validate(_ record: [String: Any]) throws {
        guard record["schemaVersion"] as? Int == 1, record["data"] is [String: Any], record["updatedAt"] is String else {
            throw MusicError.unavailable("同步设置格式不兼容；未修改本地或服务器配置。")
        }
    }
    static func merge(_ visual: VisualSettings, into existing: [String: Any]?) throws -> [String: Any] {
        _ = try visual.validated()
        if let existing { try validate(existing) }
        var record = existing ?? ["schemaVersion": 1]
        var data = record["data"] as? [String: Any] ?? [:]
        data["visualizerMode"] = visual.renderer
        data["visualizerBackgroundMode"] = visual.background
        data["showSubtitleTranslation"] = visual.showTranslation
        data["hidePlayerTranslationSubtitle"] = !visual.showTranslation
        data["subtitleContentMode"] = visual.showRomanization ? (visual.showTranslation ? "both" : "romanization") : (visual.showTranslation ? "translation" : "none")
        data["lyricsFontScale"] = visual.fontSize / 36
        if let tunings = visual.visualizerTunings {
            let encoded = try JSONEncoder().encode(tunings)
            guard let updates = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw MusicError.invalidResponse }
            let backgroundKeys = Set(["monet", "nomand", "latent", "sora"].map { $0 + "_background" })
            let rendererUpdates = updates.filter { !backgroundKeys.contains($0.key) }
            if !rendererUpdates.isEmpty {
                let existingBundle = Self.tuningBundle(data).filter { !backgroundKeys.contains($0.key) }
                data["visualizerTunings"] = Self.mergeObjects(rendererUpdates, into: existingBundle)
            }
            for mode in ["monet", "nomand", "latent", "sora"] {
                if let value = updates[mode + "_background"] as? [String: Any] {
                    data[mode + "BackgroundTuning"] = Self.mergeObjects(value, into: data[mode + "BackgroundTuning"] as? [String: Any] ?? [:])
                }
            }
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        record["updatedAt"] = formatter.string(from: Date()); record["data"] = data
        return record
    }
    static func visualSettings(_ record: [String: Any], existing: VisualSettings) throws -> VisualSettings {
        try validate(record)
        let data = record["data"] as? [String: Any] ?? [:]
        var visual = existing
        if let renderer = data["visualizerMode"] as? String { visual.renderer = renderer }
        if let background = data["visualizerBackgroundMode"] as? String { visual.background = background }
        else if data["visualizerBackgroundMode"] is NSNull { visual.background = "common" }
        if let scale = data["lyricsFontScale"] as? NSNumber {
            let size = scale.doubleValue * 36
            guard size.isFinite, (14...96).contains(size) else { throw MusicError.invalidResponse }
            visual.fontSize = size
        }
        if let show = data["showSubtitleTranslation"] as? Bool { visual.showTranslation = show }
        if let content = data["subtitleContentMode"] as? String {
            visual.showRomanization = ["both", "romanization"].contains(content)
            visual.showTranslation = ["both", "translation"].contains(content)
        }
        let tunings = Self.tuningBundle(data)
        if !tunings.isEmpty {
            visual.visualizerTunings = try JSONDecoder().decode([String: [String: TuningValue]].self, from: JSONSerialization.data(withJSONObject: tunings))
        }
        return try visual.validated()
    }
}

struct FoliaSyncCredentials {
    private let service = "Folia.sync.token"
    func read() -> String {
        var query = base; query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    func save(_ token: String) throws {
        var query = base
        let data = Data(token.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MusicError.unavailable("无法保存同步令牌。") }
    }
    private var base: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "sync-server"] }
}
