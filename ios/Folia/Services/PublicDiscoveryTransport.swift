import Foundation
// ios/Folia/Services/PublicDiscoveryTransport.swift

actor PublicDiscoveryTransport {
    private let network: URLSession
    private let mid: String
    var kugouSession: ProviderSession
    var generation = 0
    init() {
        kugouSession = (try? SessionVault().read(.kugou)) ?? ProviderSession()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        network = URLSession(configuration: config)
        if let saved = UserDefaults.standard.string(forKey: "kugou.deviceMID") { mid = saved }
        else {
            let created = ProtocolCrypto.md5(UUID().uuidString)
            mid = created
            UserDefaults.standard.set(created, forKey: "kugou.deviceMID")
        }
    }
    func search(_ query: String, provider: MusicProvider) async throws -> [Track] {
        if provider == .qq { return try await searchQQ(query) }
        let response = try await kugou("/v3/search/song", params: ["albumhide": "0", "iscorrection": "1", "keyword": query,
            "nocollect": "0", "page": "1", "pagesize": "30", "platform": "AndroidFilter"], router: "complexsearch.kugou.com")
        let data = response["data"] as? [String: Any] ?? [:]
        return (data["info"] as? [[String: Any]] ?? data["lists"] as? [[String: Any]] ?? []).compactMap { item in
            guard let hash = item["hash"] as? String ?? item["FileHash"] as? String else { return nil }
            let artwork = (item["Image"] as? String)?.replacingOccurrences(of: "{size}", with: "480")
            return Track(mediaID: hash, provider: .kugou, title: item["songname"] as? String ?? item["SongName"] as? String ?? "歌曲",
                artist: item["singername"] as? String ?? item["SingerName"] as? String ?? "",
                album: item["album_name"] as? String ?? item["AlbumName"] as? String ?? "",
                artworkURL: artwork.flatMap(URL.init(string:)), duration: item["duration"] as? Double ?? 0)
        }
    }
    func stream(_ track: Track, quality: AudioQuality) async throws -> AudioSource {
        guard track.provider == .kugou else { throw MusicError.unsupported("QQ 音乐播放授权尚未完成。") }
        let hash = track.mediaID.lowercased()
        let key = ProtocolCrypto.md5("\(hash)57ae12eb6890223e355ccfcb74edf70d1005\(mid)0")
        let result = try await kugou("/v5/url", params: ["album_id": "0", "area_code": "1", "hash": hash,
            "ssa_flag": "is_fromtrack", "version": "11430", "page_id": "151369488",
            "quality": quality == .standard ? "128" : quality == .high ? "320" : "flac", "album_audio_id": "0",
            "behavior": "play", "pid": "2", "cmd": "26", "pidversion": "3001", "IsFreePart": "0",
            "ppage_id": "463467626,350369493,788954147", "cdnBackup": "1", "module": "", "clientver": "11430", "key": key], router: "trackercdn.kugou.com")
        let values = result["url"] as? [String] ?? []
        guard let first = values.first, let url = URL(string: first) else {
            throw MusicError.unavailable("酷狗未返回可播放地址，可能需要授权或会员。")
        }
        return AudioSource(url: url, expiresAt: Date().addingTimeInterval(300))
    }
    func lyrics(_ track: Track) async throws -> LyricsPayload {
        guard track.provider == .kugou else { throw MusicError.unsupported("QQ 音乐歌词协议尚未完成。") }
        let search = try await kugou("/v1/search", params: ["album_audio_id": "0", "appid": "1005", "clientver": "20489",
            "duration": String(Int(track.duration * 1000)), "hash": track.mediaID, "keyword": "\(track.artist) \(track.title)",
            "lrctxt": "1", "man": "no"], base: "https://lyrics.kugou.com", defaults: false)
        guard let candidate = (search["candidates"] as? [[String: Any]])?.first,
              let id = OmniService.identifier(candidate["id"]), let access = candidate["accesskey"] as? String else { return LyricsPayload() }
        let downloaded = try await kugou("/download", params: ["ver": "1", "client": "android", "id": id,
            "accesskey": access, "fmt": "lrc", "charset": "utf8"], base: "https://lyrics.kugou.com")
        guard let content = downloaded["content"] as? String, let data = Data(base64Encoded: content) else { return LyricsPayload() }
        return LyricsPayload(original: String(decoding: data, as: UTF8.self))
    }
    // KuGouMusicApi 1.6.0 android signature includes sorted unescaped values and exact body bytes.
    func kugou(_ path: String, params: [String: String], router: String? = nil,
               base: String = "https://gateway.kugou.com", defaults: Bool = true, web: Bool = false,
               body: [String: Any]? = nil) async throws -> [String: Any] {
        let time = String(Int(Date().timeIntervalSince1970))
        var fields = defaults ? ["dfid": "-", "mid": mid, "uuid": "-", "appid": "1005", "clientver": "20489", "clienttime": time] : [:]
        fields.merge(params) { _, new in new }
        if let token = kugouSession.cookies["token"] { fields["token"] = token }
        if let userid = kugouSession.cookies["userid"] { fields["userid"] = userid }
        let encodedBody = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let bodyText = encodedBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        fields["signature"] = Self.kugouSignature(fields, body: bodyText, web: web)
        var components = URLComponents(string: base + path)!
        components.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        if let encodedBody {
            request.httpMethod = "POST"
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(router, forHTTPHeaderField: "x-router")
        request.setValue(mid, forHTTPHeaderField: "mid")
        request.setValue("-", forHTTPHeaderField: "dfid")
        request.setValue(time, forHTTPHeaderField: "clienttime")
        request.setValue("1", forHTTPHeaderField: "kg-rc")
        request.setValue("5d816a0", forHTTPHeaderField: "kg-thash")
        request.setValue("1", forHTTPHeaderField: "kg-rec")
        request.setValue("B9EDA08A64250DEFFBCADDEE00F8F25F", forHTTPHeaderField: "kg-rf")
        let captured = generation
        let result = try await send(request)
        guard captured == generation else { throw MusicError.sessionChanged }
        if let status = result["status"] as? Int, status == 0 {
            throw MusicError.server(result["error_code"] as? Int ?? result["errcode"] as? Int ?? -1,
                result["error"] as? String ?? result["message"] as? String ?? "酷狗拒绝了请求")
        }
        return result
    }
    nonisolated static func kugouSignature(_ params: [String: String], body: String = "", web: Bool = false) -> String {
        let salt = web ? "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt" : "OIlwieks28dk2k092lksi2UIkp"
        return ProtocolCrypto.md5(salt + params.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined() + (web ? "" : body) + salt)
    }
    private func searchQQ(_ query: String) async throws -> [Track] {
        let body: [String: Any] = ["comm": ["ct": 11, "cv": "1003006", "v": "1003006", "tmeAppID": "qqmusiclight",
            "nettype": "NETWORK_WIFI", "udid": "0", "uid": "0"],
            "req_0": ["module": "music.search.SearchCgiService", "method": "DoSearchForQQMusicLite", "param": [
                "search_id": String(UInt64.random(in: 100000000000000000...999999999999999999)), "remoteplace": "search.android.keyboard",
                "query": query, "search_type": 0, "num_per_page": 20, "page_num": 1, "highlight": 0, "nqc_flag": 0, "page_id": 1, "grp": 1]]]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("tmeLoginType=-1", forHTTPHeaderField: "Cookie")
        request.setValue("okhttp/3.14.9", forHTTPHeaderField: "User-Agent")
        let result = try await send(request)
        guard result["code"] as? Int == 0, let part = result["req_0"] as? [String: Any] else { throw MusicError.invalidResponse }
        guard part["code"] as? Int == 0 else { throw MusicError.server(part["code"] as? Int ?? -1, "QQ 音乐匿名搜索被拒绝，设备端登录尚未完成") }
        let data = part["data"] as? [String: Any] ?? [:]
        if let code = data["code"] as? Int, code != 0 { throw MusicError.server(code, "QQ 音乐搜索需要登录") }
        let songs = (data["body"] as? [String: Any])?["item_song"] as? [[String: Any]] ?? []
        return songs.compactMap { item in
            guard let id = item["mid"] as? String else { return nil }
            let album = item["album"] as? [String: Any] ?? [:]
            let artists = item["singer"] as? [[String: Any]] ?? []
            let artwork = (album["mid"] as? String).flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\($0).jpg") }
            return Track(mediaID: id, provider: .qq, title: item["title"] as? String ?? item["name"] as? String ?? "歌曲",
                artist: artists.compactMap { $0["name"] as? String }.joined(separator: " / "),
                album: album["name"] as? String ?? "", artworkURL: artwork, duration: item["interval"] as? Double ?? 0)
        }
    }
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw MusicError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MusicError.server(response.statusCode, "音乐平台网络请求失败") }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicError.invalidResponse }
        return value
    }
}

