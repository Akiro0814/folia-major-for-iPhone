import Foundation
// ios/Folia/Services/QQProvider.swift

actor QQProvider {
    let network = URLSession(configuration: .ephemeral)
    var session: ProviderSession
    var device: QQDevice
    var generation = 0
    var qrTask: Task<Void, Never>?
    var qrHeartbeat: Task<Void, Never>?
    var qrSocket: QQSocket?
    var qrStatus: QRLoginStatus = .waiting
    var qrKey: String?
    var qrError: Error?
    init() {
        let stored = (try? SessionVault().read(.qq)) ?? ProviderSession()
        session = stored
        device = QQDevice(fields: stored.cookies.filter { $0.key.hasPrefix("device.") }.reduce(into: [:]) { $0[String($1.key.dropFirst(7))] = $1.value })
    }
    func account() -> MusicAccount? { session.account }
    func logout() throws {
        cancelQR()
        generation += 1
        session = ProviderSession()
        try persist()
    }
    func persist() throws {
        for (key, value) in device.fields { session.cookies["device." + key] = value }
        try SessionVault().write(session, provider: .qq)
    }
    // All QQ RPC calls keep device binding and credential type together, including WeChat type 1.
    func call(_ module: String, _ method: String, _ params: [String: Any], auth: Bool = true,
              overrides: [String: Any] = [:]) async throws -> [String: Any] {
        let captured = generation
        if auth, session.account == nil { throw MusicError.authenticationRequired }
        let credentials = auth ? session.cookies : [:]
        let payload: [String: Any] = ["comm": device.comm(credential: credentials, overrides: overrides),
            "req_0": ["module": module, "method": method, "param": params]]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QQMusic 14090008(android 10)", forHTTPHeaderField: "User-Agent")
        if !auth, overrides["tmeAppID"] as? String == "qqmusiclight" {
            request.setValue("tmeLoginType=-1", forHTTPHeaderField: "Cookie")
            request.setValue("okhttp/3.14.9", forHTTPHeaderField: "User-Agent")
        }
        if let key = credentials["musickey"] {
            let id = credentials["str_musicid"] ?? credentials["musicid"] ?? "0"
            request.setValue("uin=\(id); qqmusic_uin=\(id); qm_keyst=\(key); qqmusic_key=\(key)", forHTTPHeaderField: "Cookie")
        }
        let result = try await json(request)
        guard captured == generation else { throw MusicError.sessionChanged }
        guard result["code"] as? Int == 0, let item = result["req_0"] as? [String: Any] else { throw MusicError.invalidResponse }
        guard item["code"] as? Int == 0 else {
            let code = item["code"] as? Int ?? -1
            if [2001, 1000, 100001].contains(code) { throw MusicError.authenticationRequired }
            throw MusicError.server(code, "QQ 音乐拒绝了请求")
        }
        guard let data = item["data"] as? [String: Any] else { throw MusicError.invalidResponse }
        return data
    }
    func bootstrap() async throws {
        let now = Date().timeIntervalSince1970
        if device.fields["qimei"] == nil || now - (Double(device.fields["qimeiSavedAt"] ?? "0") ?? 0) > 86400 {
            let result = try await json(device.qimeiRequest())
            let inner = Self.dictionary(result["data"])
            let data = Self.dictionary(inner["data"])
            guard let q16 = data["q16"] as? String, let q36 = data["q36"] as? String else {
                throw MusicError.server(result["code"] as? Int ?? -1, "QQ 音乐设备协议被拒绝，请检查系统时间或稍后重试")
            }
            device.fields["qimei"] = q16
            device.fields["qimei36"] = q36
            device.fields["qimeiSavedAt"] = String(now)
        }
        let status = try await call("music.getSession.session", "GetSession", ["uid": device.fields["uid"] ?? "", "vkey": 0, "caller": 0], auth: false)
        let data = Self.dictionary(status["session"])
        guard let uid = OmniService.identifier(data["uid"]), let sid = OmniService.identifier(data["sid"]) else { throw MusicError.invalidResponse }
        device.fields["uid"] = uid
        device.fields["sid"] = sid
        try persist()
    }
    func startWechatQR() async throws -> QRLogin {
        cancelQR()
        generation += 1
        let captured = generation
        try await bootstrap()
        var url = URLComponents(string: "https://open.weixin.qq.com/connect/qrconnect")!
        url.queryItems = ["appid": "wx48db31d50e334801", "redirect_uri": "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/",
            "response_type": "code", "scope": "snsapi_login", "state": "STATE", "href": "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect"]
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let page = try await text(URLRequest(url: url.url!))
        guard captured == generation else { throw MusicError.sessionChanged }
        guard let match = page.range(of: "uuid=([^\"]+)\"", options: .regularExpression) else { throw MusicError.invalidResponse }
        let uuid = String(page[match]).dropFirst(5).dropLast()
        let key = String(uuid)
        guard let confirm = URL(string: "https://open.weixin.qq.com/connect/confirm?uuid=\(key)"),
              let image = URL(string: "https://open.weixin.qq.com/connect/qrcode/\(key)") else { throw MusicError.invalidResponse }
        return QRLogin(key: key, url: confirm, imageURL: image)
    }
    func pollWechatQR(_ login: QRLogin) async throws -> QRLoginStatus {
        let captured = generation
        var url = URLComponents(string: "https://lp.open.weixin.qq.com/connect/l/qrconnect")!
        url.queryItems = [URLQueryItem(name: "uuid", value: login.key), URLQueryItem(name: "_", value: String(Int64(Date().timeIntervalSince1970 * 1000)))]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 5
        request.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")
        let content: String
        do { content = try await text(request) }
        catch let error as URLError where error.code == .timedOut { return .waiting }
        guard captured == generation else { throw MusicError.sessionChanged }
        let pattern = "window\\.wx_errcode=(\\d+);window\\.wx_code='([^']*)'"
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let statusRange = Range(match.range(at: 1), in: content), let codeRange = Range(match.range(at: 2), in: content) else { throw MusicError.invalidResponse }
        switch Int(content[statusRange]) {
        case 408: return .waiting
        case 404: return .scanned
        case 402, 403: return .expired
        case 405:
            let result = try await call("music.login.LoginServer", "Login", ["code": String(content[codeRange]), "strAppid": "wx48db31d50e334801"], auth: false, overrides: ["tmeLoginType": 1])
            guard captured == generation else { throw MusicError.sessionChanged }
            return .authorized(try await establish(result, type: 1))
        default: throw MusicError.server(Int(content[statusRange]) ?? -1, "微信返回了未知扫码状态")
        }
    }
    func establish(_ result: [String: Any], type: Int) async throws -> MusicAccount {
        let captured = generation
        let previous = session
        guard let key = result["musickey"] as? String,
              let id = OmniService.identifier(result["str_musicid"]) ?? OmniService.identifier(result["musicid"]), id != "0" else { throw MusicError.authenticationRequired }
        let account = MusicAccount(id: id, provider: .qq, nickname: result["nick"] as? String ?? result["nickname"] as? String ?? "QQ 音乐用户",
            avatarURL: (result["logo"] as? String).flatMap(URL.init(string:)))
        session.account = account
        for (name, value) in result { if let value = OmniService.identifier(value) { session.cookies[name] = value } }
        session.cookies["musickey"] = key
        session.cookies["loginType"] = String(type)
        do {
            _ = try await call("music.UserInfo.userInfoServer", "GetLoginUserInfo", [:])
            try persist()
            return account
        } catch {
            if captured == generation { session = previous }
            throw error
        }
    }
    func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw MusicError.unavailable("QQ 音乐网络请求失败") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicError.invalidResponse }
        return result
    }
    func text(_ request: URLRequest) async throws -> String {
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw MusicError.invalidResponse }
        return String(decoding: data, as: UTF8.self)
    }
    static func dictionary(_ value: Any?) -> [String: Any] {
        if let dict = value as? [String: Any] { return dict }
        if let string = value as? String, let data = string.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return dict }
        return [:]
    }
}



