import Foundation
// ios/Folia/Services/KuGouAuthentication.swift

extension PublicDiscoveryTransport {
    func kugouAccount() -> MusicAccount? { kugouSession.account }
    func logoutKugou() throws {
        generation += 1
        kugouSession = ProviderSession()
        try SessionVault().write(kugouSession, provider: .kugou)
    }
    func sendKugouCode(phone: String) async throws {
        _ = try await kugou("/v7/send_mobile_code", params: [:], base: "https://login.user.kugou.com",
            body: ["businessid": 5, "mobile": phone, "plat": 3])
    }
    func loginKugou(phone: String, credential: String, method: LoginMethod) async throws -> MusicAccount {
        generation += 1
        let captured = generation
        let time = Int64(Date().timeIntervalSince1970 * 1000)
        if method == .password { return try await passwordKugou(username: phone, password: credential, time: time, captured: captured) }
        let encrypted = try KuGouCrypto.encrypt(["mobile": phone, "code": credential], time: time)
        let masked = String(phone.prefix(2)) + "*****" + String(phone.suffix(1))
        let body: [String: Any] = ["plat": 1, "support_multi": 1, "t1": 0, "t2": 0, "clienttime_ms": time,
            "mobile": masked, "key": ProtocolCrypto.md5("1005OIlwieks28dk2k092lksi2UIkp20489\(time)"),
            "pk": encrypted.pk, "params": encrypted.cipher, "t3": "MCwwLDAsMCwwLDAsMCwwLDA="]
        let result = try await kugou("/v7/login_by_verifycode", params: [:], base: "https://loginserviceretry.kugou.com", body: body)
        guard captured == generation else { throw MusicError.sessionChanged }
        return try saveKugou(result, encryptionKey: encrypted.key)
    }
    func startKugouQR() async throws -> QRLogin {
        let result = try await kugou("/v2/qrcode", params: ["appid": "1001", "type": "1", "plat": "4",
            "qrcode_txt": "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=1005&", "srcappid": "2919"],
            base: "https://login-user.kugou.com", web: true)
        guard let data = result["data"] as? [String: Any], let key = data["qrcode"] as? String,
              let url = URL(string: "https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=\(key)") else { throw MusicError.invalidResponse }
        return QRLogin(key: key, url: url)
    }
    func pollKugouQR(_ login: QRLogin) async throws -> QRLoginStatus {
        let result = try await kugou("/v2/get_userinfo_qrcode", params: ["plat": "4", "appid": "1005", "srcappid": "2919", "qrcode": login.key],
            base: "https://login-user.kugou.com", web: true)
        guard let data = result["data"] as? [String: Any] else { throw MusicError.invalidResponse }
        switch data["status"] as? Int {
        case 0: return .expired
        case 2: return .scanned
        case 4: return .authorized(try saveKugou(result))
        default: return .waiting
        }
    }
    private func saveKugou(_ response: [String: Any], encryptionKey: String? = nil) throws -> MusicAccount {
        guard var data = response["data"] as? [String: Any] else { throw MusicError.invalidResponse }
        if let encrypted = data["secu_params"] as? String, let encryptionKey {
            let decoded = try KuGouCrypto.decrypt(encrypted, key: encryptionKey)
            if let fields = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] { data.merge(fields) { _, new in new } }
            else { data["token"] = String(decoding: decoded, as: UTF8.self) }
        }
        guard let token = data["token"] as? String, !token.isEmpty,
              let id = OmniService.identifier(data["userid"]), id != "0" else { throw MusicError.authenticationRequired }
        let account = MusicAccount(id: id, provider: .kugou,
            nickname: data["nickname"] as? String ?? data["username"] as? String ?? "酷狗用户",
            avatarURL: (data["pic"] as? String).flatMap(URL.init(string:)))
        kugouSession.account = account
        kugouSession.cookies["token"] = token
        kugouSession.cookies["userid"] = id
        for name in ["vip_token", "vip_type", "t1"] {
            if let value = OmniService.identifier(data[name]) { kugouSession.cookies[name] = value }
        }
        try SessionVault().write(kugouSession, provider: .kugou)
        return account
    }
    private func passwordKugou(username: String, password: String, time: Int64, captured: Int) async throws -> MusicAccount {
        let encrypted = try KuGouCrypto.encrypt(["pwd": password, "code": "", "clienttime_ms": time], time: time)
        let result = try await kugou("/v9/login_by_pwd", params: [:], router: "login.user.kugou.com", body: [
            "plat": 1, "support_multi": 1, "clienttime_ms": time, "t1": Self.passwordT1, "t2": Self.passwordT2,
            "t3": "MCwwLDAsMCwwLDAsMCwwLDA=", "username": username, "params": encrypted.cipher, "pk": encrypted.pk])
        guard captured == generation else { throw MusicError.sessionChanged }
        return try saveKugou(result, encryptionKey: encrypted.key)
    }
    // Pinned KuGouMusicApi 1.6.0 password protocol fingerprints, not user credentials.
    private static let passwordT1 = "562a6f12a6e803453647d16a08f5f0c2ff7eee692cba2ab74cc4c8ab47fc467561a7c6b586ce7dc46a63613b246737c03a1dc8f8d162d8ce1d2c71893d19f1d4b797685a4c6d3d81341cbde65e488c4829a9b4d42ef2df470eb102979fa5adcdd9b4eecfea8b909ff7599abeb49867640f10c3c70fc444effca9d15db44a9a6c907731e2bb0f22cd9b3536380169995693e5f0e2424e3378097d3813186e3fe96bbe7023808a0981b4e2b6135a76faac"
    private static let passwordT2 = "31c4daf4cf480169ccea1cb7d4a209295865a9d2b788510301694db229b87807469ea0d41b4d4b9173c2151da7294aeebfc9738df154bbdf11a4e117bb5dff6a3af8ce5ce333e681c1f29a44038f27567d58992eb81283e080778ac77db1400fdf49b7cf7e26be2e5af4da7830cc3be4"
}

