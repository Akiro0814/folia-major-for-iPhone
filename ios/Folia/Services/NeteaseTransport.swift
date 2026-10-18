import Foundation
// ios/Folia/Services/NeteaseTransport.swift

actor NeteaseTransport {
    private let vault = SessionVault()
    private var session: ProviderSession
    private var generation = 0
    private var pendingCookies: [String: String] = [:]
    private let network: URLSession
    init(initialSession: ProviderSession? = nil) {
        session = initialSession ?? (try? SessionVault().read(.netease)) ?? ProviderSession()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        network = URLSession(configuration: config)
    }
    func account() -> MusicAccount? { session.account }
    func logout() throws {
        generation += 1
        session = ProviderSession()
        pendingCookies = [:]
        try vault.write(session, provider: .netease)
    }
    func beginAuthentication() -> Int {
        generation += 1
        pendingCookies = [:]
        return generation
    }
    func cancelAuthentication() {
        generation += 1
        pendingCookies = [:]
    }
    func checkAuthentication(_ expected: Int) throws {
        guard expected == generation else { throw MusicError.sessionChanged }
        try Task.checkCancellation()
    }
    func saveAccount(_ account: MusicAccount, expected: Int) throws {
        try checkAuthentication(expected)
        var next = session
        next.account = account
        next.cookies.merge(pendingCookies) { _, new in new }
        try vault.write(next, provider: .netease)
        session = next
        pendingCookies = [:]
    }
    // Cookies are kept out of URLSession disk storage and persisted only in Keychain.
    func request(_ path: String, _ payload: [String: Any] = [:], codes: Set<Int> = [200], authentication: Int? = nil) async throws -> [String: Any] {
        let capturedGeneration = generation
        if let authentication { try checkAuthentication(authentication) }
        var body = payload
        body["csrf_token"] = (authentication != nil ? pendingCookies["__csrf"] : nil) ?? session.cookies["__csrf"] ?? ""
        body["e_r"] = false
        let fields = try ProtocolCrypto.weapi(body)
        var request = URLRequest(url: URL(string: "https://music.163.com/weapi/" + path.dropFirst(5))!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        var cookies = session.cookies
        if authentication != nil { cookies.merge(pendingCookies) { _, new in new } }
        cookies["os"] = "pc"
        cookies["__remember_me"] = "true"
        request.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        var form = URLComponents()
        form.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        guard capturedGeneration == generation else { throw MusicError.sessionChanged }
        guard let http = response as? HTTPURLResponse else { throw MusicError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MusicError.server(http.statusCode, "网络请求失败") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicError.invalidResponse }
        let code = (result["code"] as? NSNumber)?.intValue ?? 200
        guard codes.contains(code) else {
            if code == 301 || code == 302 { throw MusicError.authenticationRequired }
            throw MusicError.server(code, result["message"] as? String ?? result["msg"] as? String ?? "平台拒绝了请求")
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { target, entry in
            target[String(describing: entry.key)] = String(describing: entry.value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: request.url!) {
            if authentication != nil { pendingCookies[cookie.name] = cookie.value }
            else { session.cookies[cookie.name] = cookie.value }
        }
        if authentication == nil, !session.cookies.isEmpty { try vault.write(session, provider: .netease) }
        return result
    }
}

