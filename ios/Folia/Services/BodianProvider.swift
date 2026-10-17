import Foundation
// ios/Folia/Services/BodianProvider.swift

/// Direct port of the installed bodian-music-api 0.1.2 endpoints; no hosted Node dependency.
actor BodianProvider {
    private let session: URLSession
    private var saved: ProviderSession
    private var generation = UUID()
    private var pendingQR: (key: String, expires: Date)?
    private let deviceID: String
    init(session: URLSession = .shared) {
        self.session = session
        saved = (try? SessionVault().read(.bodian)) ?? ProviderSession()
        let defaults = UserDefaults.standard
        let device = defaults.string(forKey: "folia.bodian.device") ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        deviceID = device; defaults.set(device, forKey: "folia.bodian.device")
    }
    func account() -> MusicAccount? {
        guard saved.cookies["uid"] == saved.account?.id, saved.cookies["token"]?.isEmpty == false else { return nil }
        return saved.account
    }
    func logout() throws {
        try SessionVault().write(ProviderSession(), provider: .bodian)
        saved = ProviderSession(); pendingQR = nil; generation = UUID()
    }
    func search(_ query: String) async throws -> [Track] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 500 else { return [] }
        let result = try await data("/api/search/music/list", fields: [("keyword", query), ("correct", "1"), ("pn", "0"), ("rn", "100")])
        guard let songs = result["resultList"] as? [[String: Any]] else { throw MusicError.invalidResponse }
        return songs.compactMap(Self.normalize)
    }
    func stream(for track: Track, quality: AudioQuality = .high) async throws -> AudioSource {
        guard track.provider == .bodian else { throw MusicError.invalidResponse }
        let id = try Self.mediaID(track.mediaID), freeSign = track.providerData["freeSign"] ?? ""
        guard freeSign.utf8.count <= 4096 else { throw MusicError.invalidResponse }
        let revision = generation
        let rights = try await data("/api/play/music/v2/checkRight", fields: [("musicId", track.mediaID), ("freeSign", freeSign)],
                                   body: ["musicId": id, "freeSign": freeSign], signed: true)
        try Self.validateRights(rights)
        guard revision == generation else { throw MusicError.sessionChanged }
        let format = quality == .lossless ? "flac" : "mp3"
        let bitrate = quality == .standard ? "128kmp3" : quality == .high ? "320kmp3" : "2000kflac"
        let body: [String: Any] = ["devId": deviceID, "musicId": id, "format": format, "br": bitrate, "freeSign": freeSign]
        let audio = try await data("/api/play/music/v2/audioUrl", fields: [("devId", deviceID), ("musicId", track.mediaID), ("format", format), ("br", bitrate), ("freeSign", freeSign)], body: body, signed: true)
        guard revision == generation else { throw MusicError.sessionChanged }
        guard let value = audio["audioHttpsUrl"] as? String ?? audio["audioUrl"] as? String, let url = URL(string: value),
              ["https", "http"].contains(url.scheme ?? ""), url.user == nil, url.password == nil else { throw MusicError.invalidResponse }
        return AudioSource(url: url)
    }
    func lyrics(for track: Track) async throws -> LyricsPayload {
        guard track.provider == .bodian else { throw MusicError.invalidResponse }; _ = try Self.mediaID(track.mediaID)
        let query = "type=lyric&req=2&lrcx=1&rid=\(track.mediaID)&songname=&artist=&corp=kuwo&fromchannel=bodian"
        let result = try await data("/mobi.s", fields: [("f", "bodian"), ("q", Data(query.utf8).base64EncodedString())], lyric: true)
        guard let value = result["content"] as? String, let bytes = Data(base64Encoded: value), let text = String(data: bytes, encoding: .utf8) else { throw MusicError.invalidResponse }
        return Self.decodeLyrics(text)
    }
    func startQR() async throws -> QRLogin {
        let result = try await data("/api/ucenter/login/qrCode", signed: true, anonymous: true)
        guard let key = result["qrCode"] as? String, !key.isEmpty else { throw MusicError.invalidResponse }
        pendingQR = (key, Date().addingTimeInterval(300))
        let value = "https://bodian-oia.kuwo.cn/bodian/download.html?" + Self.queryString([("pageName", "login_pc"), ("pt", "3"), ("id", key)])
        guard let url = URL(string: value) else { throw MusicError.invalidResponse }; return QRLogin(key: key, url: url)
    }
    func pollQR(_ login: QRLogin) async throws -> QRLoginStatus {
        guard let pendingQR, pendingQR.key == login.key, pendingQR.expires > Date() else { return .expired }
        let revision = generation
        let result = try await data("/api/ucenter/login/qrCodeStatus", fields: [("qrCode", login.key)], signed: true, anonymous: true)
        guard revision == generation, self.pendingQR?.key == login.key else { return .expired }
        switch Self.number(result["status"]) {
        case 1: return .waiting
        case 2: self.pendingQR = nil; return .expired
        case 3:
            let exchange: [String: Any]
            do { exchange = try await data("/api/ucenter/users/login", body: ["authType": 10, "qrCode": login.key], method: "POST", signed: true, anonymous: true) }
            catch MusicError.server(11027, _) { return .scanned }
            try Task.checkCancellation()
            guard revision == generation, self.pendingQR?.key == login.key else { return .expired }
            let account = try Self.loginAccount(exchange)
            let new = ProviderSession(account: account, cookies: ["uid": account.id, "token": exchange["token"] as? String ?? ""])
            try SessionVault().write(new, provider: .bodian)
            saved = new; self.pendingQR = nil; generation = UUID()
            return .authorized(account)
        default: throw MusicError.invalidResponse
        }
    }
    func playlists() async throws -> [MusicCollection] {
        guard let user = account() else { throw MusicError.authenticationRequired }
        let fields = [("userId", user.id), ("fromUid", user.id)]
        let owned = try await data("/api/service/playlist/userCreate", fields: fields)
        let liked = try await data("/api/service/playlist/fond", fields: fields)
        let collected = try await data("/api/service/collect/4/list", fields: fields + [("pn", "1"), ("rn", "100")])
        var entries = (owned["playLists"] as? [[String: Any]] ?? []).compactMap { Self.collection($0, owned: true) }
        if let fond = Self.collection(liked, owned: true) { entries.append(fond) }
        entries += (collected["playLists"] as? [[String: Any]] ?? []).filter { Self.number($0["sourceType"]) != 6 }.compactMap { Self.collection($0) }
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }
    func tracks(in collection: MusicCollection) async throws -> [Track] {
        guard collection.provider == .bodian else { throw MusicError.invalidResponse }; _ = try Self.mediaID(collection.id)
        let source = collection.providerData["source"] ?? "4"
        guard ["1", "2", "3", "4", "5", "6"].contains(source) else { throw MusicError.invalidResponse }
        var result: [Track] = []
        for page in 1...1000 {
            try Task.checkCancellation()
            let pageData = try await data("/api/service/playlist/\(collection.id)/musicList", fields: [("source", source), ("pn", String(page)), ("rn", "100")])
            guard let entries = pageData["list"] as? [[String: Any]] else { throw MusicError.invalidResponse }
            result += entries.compactMap(Self.normalize)
            let total = Self.number(pageData["total"])
            if entries.isEmpty || (total.map { page * 100 >= $0 } ?? (entries.count < 100)) { break }
        }
        return result
    }
    func recommendations() async throws -> [Track] {
        let result = try await data("/api/service/music/recommendList")
        return (result["musicList"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
    }
    func setLiked(_ liked: Bool, track: Track) async throws {
        guard let user = account() else { throw MusicError.authenticationRequired }
        let revision = generation
        let fond = try await data("/api/service/playlist/fond", fields: [("userId", user.id)])
        guard let id = OmniService.identifier(fond["id"]) else { throw MusicError.invalidResponse }
        try await mutate(id: id, track: track, add: liked, revision: revision)
    }
    func changePlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard collection.provider == .bodian, let user = account() else { throw MusicError.authenticationRequired }
        let revision = generation
        let owned = try await data("/api/service/playlist/userCreate", fields: [("userId", user.id)])
        let found = (owned["playLists"] as? [[String: Any]] ?? []).contains { OmniService.identifier($0["id"]) == collection.id }
        if !found {
            let fond = try await data("/api/service/playlist/fond", fields: [("userId", user.id)])
            guard OmniService.identifier(fond["id"]) == collection.id else { throw MusicError.unsupported("只能编辑当前波点账号拥有的歌单。") }
        }
        try await mutate(id: collection.id, track: track, add: add, revision: revision)
    }
    private func mutate(id: String, track: Track, add: Bool, revision: UUID) async throws {
        guard track.provider == .bodian, revision == generation else { throw MusicError.sessionChanged }
        let playlist = try Self.mediaID(id), song = try Self.mediaID(track.mediaID)
        _ = try await data("/api/service/playlist/music" + (add ? "" : "/delete"), body: ["playListId": playlist, "musicIdList": [song]], method: "POST", signed: true)
    }
    func data(_ path: String, fields: [(String, String)] = [], body: [String: Any]? = nil, method: String = "GET", signed: Bool = false, anonymous: Bool = false, lyric: Bool = false) async throws -> [String: Any] {
        let revision = generation
        let user = anonymous ? nil : account()
        let token = user == nil ? "" : saved.cookies["token"] ?? ""
        var fields = fields + [("uid", user?.id ?? "-1"), ("token", token)]
        let encodedBody = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let text = encodedBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        if signed { fields.append(("timestamp", String(Int64(Date().timeIntervalSince1970 * 1000)))); fields.append(("sign", Self.signature(path: path, fields: fields, body: text))) }
        guard let url = URL(string: (lyric ? "https://mlyric.kuwo.cn" : "https://bd-api.kuwo.cn") + path + "?" + Self.queryString(fields)) else { throw MusicError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = encodedBody; request.timeoutInterval = 30
        let headers = ["User-Agent": "Dart/3.3 (dart:io)", "plat": "win", "channel": "W1", "ver": "1.1.7", "svrver": "13", "api-ver": "application/json", "brand": "Windows", "net": "wifi", "devid": deviceID, "qimei36": deviceID, "Content-Type": "application/json"]
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let user { request.setValue(user.id, forHTTPHeaderField: "uid"); request.setValue(token, forHTTPHeaderField: "token") }
        let bytes: Data
        if method == "GET", encodedBody != nil { bytes = try await BodianGETBodyHTTP().send(request) }
        else {
            let (responseBytes, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MusicError.unavailable("波点音乐网络请求失败。") }
            bytes = responseBytes
        }
        try Task.checkCancellation(); guard revision == generation else { throw MusicError.sessionChanged }
        guard bytes.count < 8 * 1024 * 1024, let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw MusicError.invalidResponse }
        guard Self.number(root["code"]) == 200 else { throw MusicError.server(Self.number(root["code"]) ?? -1, root["msg"] as? String ?? root["message"] as? String ?? "波点音乐拒绝了请求") }
        guard let value = root["data"] as? [String: Any] else {
            if root["data"] == nil || root["data"] is NSNull || (root["data"] as? [Any])?.isEmpty == true { return [:] }
            throw MusicError.invalidResponse
        }
        return value
    }
}
