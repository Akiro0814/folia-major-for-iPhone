import Foundation
// ios/Folia/Services/OmniAuthentication.swift

extension OmniService {
    func configureNavidrome(serverURL: String, username: String, password: String) async throws {
        try await navidrome.configure(serverURL: serverURL, username: username, password: password)
    }
    func sendCode(phone: String, provider: MusicProvider) async throws {
        if provider == .kugou { try await discovery.sendKugouCode(phone: phone); return }
        try requireNetease(provider)
        _ = try await netease.request("/api/sms/captcha/sent", ["cellphone": phone, "ctcode": "86", "secrete": "music_middleuser_pclogin"])
    }
    func login(phone: String, credential: String, method: LoginMethod, provider: MusicProvider) async throws -> MusicAccount {
        if provider == .kugou { return try await discovery.loginKugou(phone: phone, credential: credential, method: method) }
        try requireNetease(provider)
        guard method != .qr else { throw MusicError.unsupported("请使用扫码登录流程。") }
        var parameters: [String: Any] = ["type": "1", "https": "true", "phone": phone,
            "countrycode": "86", "remember": "true", "secureCaptcha": ""]
        parameters[method == .sms ? "captcha" : "password"] = method == .sms ? credential : ProtocolCrypto.md5(credential)
        let response = try await netease.request("/api/w/login/cellphone", parameters)
        return try await establishAccount(response)
    }
    func startQR(provider: MusicProvider) async throws -> QRLogin {
        if provider == .qq { return try await qq.startWechatQR() }
        if provider == .kugou { return try await discovery.startKugouQR() }
        try requireNetease(provider)
        let result = try await netease.request("/api/login/qrcode/unikey", ["type": 3])
        guard let key = result["unikey"] as? String,
              let url = URL(string: "https://music.163.com/login?codekey=\(key)") else { throw MusicError.invalidResponse }
        return QRLogin(key: key, url: url)
    }
    func pollQR(_ login: QRLogin, provider: MusicProvider) async throws -> QRLoginStatus {
        if provider == .qq { return try await qq.pollWechatQR(login) }
        if provider == .kugou { return try await discovery.pollKugouQR(login) }
        try requireNetease(provider)
        let result = try await netease.request("/api/login/qrcode/client/login", ["key": login.key, "type": 3], codes: [200, 800, 801, 802, 803])
        switch result["code"] as? Int {
        case 800: return .expired
        case 802: return .scanned
        case 803: return .authorized(try await establishAccount([:]))
        default: return .waiting
        }
    }
    // Resolve account from the authenticated session; a QR acknowledgement alone is not login proof.
    private func establishAccount(_ response: [String: Any]) async throws -> MusicAccount {
        let profile: [String: Any]
        if let included = response["profile"] as? [String: Any] { profile = included }
        else {
            let status = try await netease.request("/api/w/nuser/account/get")
            guard let resolved = status["profile"] as? [String: Any] else { throw MusicError.authenticationRequired }
            profile = resolved
        }
        guard let id = Self.identifier(profile["userId"]) else { throw MusicError.invalidResponse }
        let account = MusicAccount(id: id, provider: .netease, nickname: profile["nickname"] as? String ?? "网易云用户",
            avatarURL: (profile["avatarUrl"] as? String).flatMap(URL.init(string:)))
        try await netease.saveAccount(account)
        return account
    }
}



