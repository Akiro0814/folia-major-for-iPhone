import Foundation
import Security
// ios/Folia/Services/SessionVault.swift

struct ProviderSession: Codable { var account: MusicAccount?; var cookies: [String: String] = [:] }
struct SessionVault {
    private let service = "Folia.provider.sessions"
    func read(_ provider: MusicProvider) throws -> ProviderSession {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return ProviderSession() }
        guard status == errSecSuccess, let data = result as? Data else { throw MusicError.unavailable("无法读取安全账户存储。") }
        return try JSONDecoder().decode(ProviderSession.self, from: data)
    }
    func write(_ session: ProviderSession, provider: MusicProvider) throws {
        let data = try JSONEncoder().encode(session)
        let query = base(provider)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MusicError.unavailable("无法保存安全账户存储。") }
    }
    private func base(_ provider: MusicProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }
}
