import Foundation
import Security

// Folia/Services/AIThemeService.swift — user-configured compatible AI with an isolated Keychain secret.
struct AIThemeConfiguration: Codable {
    var server = ""
    var model = ""
    var apiKey = ""
}

actor AIThemeService {
    private static let keychainService = "Folia.ai.user-key"

    static func configuration() throws -> AIThemeConfiguration? {
        var query = keychainQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw MusicError.unavailable("无法读取 AI 配置。") }
        return try JSONDecoder().decode(AIThemeConfiguration.self, from: data)
    }

    static func save(_ configuration: AIThemeConfiguration?) throws {
        guard let configuration else { SecItemDelete(keychainQuery as CFDictionary); return }
        _ = try endpoint(configuration.server)
        let encoded = try JSONEncoder().encode(configuration)
        let update = [kSecValueData as String: encoded]
        var status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = keychainQuery; attributes[kSecValueData as String] = encoded
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MusicError.unavailable("无法保存 AI 配置。") }
    }
    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "configuration"]
    }

    static func endpoint(_ text: String) throws -> URL {
        guard var url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw MusicError.unavailable("请输入不含账户、查询参数的 HTTPS AI 服务地址。")
        }
        if !url.path.hasSuffix("/chat/completions") { url.append(path: "chat/completions") }
        return url
    }

    // Colors use the fixed order background, primary text, accent, secondary text across export and renderer.
    static func validate(_ colors: [String]) throws -> [String] {
        guard colors.count == 4, colors.allSatisfy({ $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else {
            throw MusicError.unavailable("AI 必须返回四个 #RRGGBB 颜色。")
        }
        return colors
    }

    func generate(configuration: AIThemeConfiguration, track: Track, lyrics: String) async throws -> [String] {
        guard !configuration.apiKey.isEmpty, !configuration.model.isEmpty else { throw MusicError.unavailable("请填写模型与 API Key。") }
        var request = URLRequest(url: try Self.endpoint(configuration.server))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = "Design a readable music player palette for \(track.title) by \(track.artist). Lyrics context: \(lyrics.prefix(3000)). Return ONLY JSON {\"colors\":[\"#RRGGBB\",\"#RRGGBB\",\"#RRGGBB\",\"#RRGGBB\"]}. Order: dark or light background, primary text with strong contrast, accent, secondary text with readable contrast."
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": configuration.model, "stream": false,
            "messages": [["role": "user", "content": prompt]]])
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 1_000_000 else {
            throw MusicError.unavailable("AI 服务请求失败，请检查地址、模型与密钥。")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any], let content = message["content"] as? String,
              let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start <= end,
              let palette = try JSONSerialization.jsonObject(with: Data(content[start...end].utf8)) as? [String: Any],
              let colors = palette["colors"] as? [String] else { throw MusicError.invalidResponse }
        return try Self.validate(colors)
    }
}
