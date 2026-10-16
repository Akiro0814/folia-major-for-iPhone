import Foundation
// ios/Folia/Services/QQCatalog.swift

extension QQProvider {
    func search(_ query: String) async throws -> [Track] {
        let result = try await call("music.search.SearchCgiService", "DoSearchForQQMusicLite", ["search_id": String(UInt64.random(in: 100000000000000000...999999999999999999)),
            "remoteplace": "search.android.keyboard", "query": query, "search_type": 0, "num_per_page": 20, "page_num": 1,
            "highlight": 0, "nqc_flag": 0, "page_id": 1, "grp": 1])
        if let code = result["code"] as? Int, code != 0 { throw MusicError.server(code, "QQ 音乐搜索失败") }
        return (Self.dictionary(result["body"])["item_song"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
    }
    func stream(for track: Track, quality: AudioQuality) async throws -> AudioSource {
        let detail = try await call("music.pf_song_detail_svr", "get_song_detail_yqq", ["song_type": 0, "song_mid": track.mediaID])
        let info = Self.dictionary(detail["track_info"])
        let file = Self.dictionary(info["file"])
        let media = file["media_mid"] as? String ?? track.mediaID
        let prefix = quality == .standard ? "M500" : quality == .high ? "M800" : "F000"
        let ext = quality == .lossless ? ".flac" : ".mp3"
        let response = try await call("music.vkey.GetVkey", "UrlGetVkey", ["filename": [prefix + track.mediaID + media + ext],
            "guid": UUID().uuidString.replacingOccurrences(of: "-", with: ""), "songmid": [track.mediaID], "songtype": [0],
            "uin": session.account?.id ?? "0", "ctx": 0])
        guard let item = (response["midurlinfo"] as? [[String: Any]])?.first,
              let path = item["purl"] as? String, !path.isEmpty else { throw MusicError.unavailable("QQ 音乐未返回可播放地址，请检查会员权限或更换音质。") }
        let domains = response["sip"] as? [String] ?? []
        let domain = domains.first(where: { !$0.hasPrefix("http://ws") }) ?? domains.first ?? "http://sjy6.stream.qqmusic.qq.com/"
        guard let url = URL(string: domain + path) else { throw MusicError.invalidResponse }
        return AudioSource(url: url, expiresAt: Date().addingTimeInterval(600))
    }
    func lyrics(for track: Track) async throws -> LyricsPayload {
        var url = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        url.queryItems = ["songmid": track.mediaID, "format": "json", "outCharset": "utf-8", "pcachetime": String(Int64(Date().timeIntervalSince1970 * 1000))]
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        let data = try await json(request)
        if let code = data["code"] as? Int, code != 0 { throw MusicError.server(code, "QQ 音乐歌词请求失败") }
        func decode(_ key: String) -> String {
            guard let encoded = data[key] as? String, let bytes = Data(base64Encoded: encoded) else { return "" }
            return String(decoding: bytes, as: UTF8.self)
        }
        return LyricsPayload(original: decode("lyric"), translation: decode("trans"))
    }
    func playlists() async throws -> [MusicCollection] {
        guard let user = session.account else { throw MusicError.authenticationRequired }
        let result = try await call("music.musicasset.PlaylistBaseRead", "GetPlaylistByUin", ["uin": user.id])
        var items = result["v_playlist"] as? [[String: Any]] ?? []
        if let uin = session.cookies["encryptUin"] {
            var offset = 0
            var seen = Set<String>()
            while true {
                let page = try await call("music.musicasset.PlaylistFavRead", "CgiGetPlaylistFavInfo", ["uin": uin, "offset": offset, "size": 100])
                let entries = page["v_list"] as? [[String: Any]] ?? []
                var fresh = 0
                for entry in entries {
                    if let id = Self.collectionID(entry), seen.insert(id).inserted { items.append(entry); fresh += 1 }
                }
                if page["hasmore"] as? Int != 1 || fresh == 0 { break }
                offset += entries.count
                try Task.checkCancellation()
            }
        }
        var seen = Set<String>()
        return items.compactMap { entry in
            guard let id = Self.collectionID(entry), seen.insert(id).inserted else { return nil }
            let title = entry["name"] as? String ?? entry["title"] as? String ?? entry["dissname"] as? String ?? "歌单"
            let cover = entry["bigpicUrl"] as? String ?? entry["picUrl"] as? String ?? entry["logo"] as? String
            return MusicCollection(id: id, provider: .qq, title: title, artworkURL: cover.flatMap(URL.init(string:)),
                trackCount: entry["songnum"] as? Int ?? entry["song_cnt"] as? Int ?? 0)
        }
    }
    func tracks(in collection: MusicCollection) async throws -> [Track] {
        var songs: [Track] = [], seen = Set<String>()
        while true {
            let response = try await call("music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo", ["disstid": collection.id,
                "userinfo": 1, "tag": 1, "orderlist": 1, "song_begin": songs.count, "song_num": 500, "onlysonglist": 0, "enc_host_uin": ""])
            let page = (response["songlist"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
            let fresh = page.filter { seen.insert($0.mediaID).inserted }
            songs += fresh
            if response["hasmore"] as? Int != 1 || fresh.isEmpty { break }
            if let total = response["total_song_num"] as? Int, songs.count >= total { break }
            try Task.checkCancellation()
        }
        return songs
    }
    static func collectionID(_ item: [String: Any]) -> String? {
        OmniService.identifier(item["tid"] ?? item["dissid"] ?? item["id"] ?? item["dirId"] ?? item["dirid"])
    }
    static func normalize(_ item: [String: Any]) -> Track? {
        guard let mid = item["mid"] as? String ?? item["songmid"] as? String else { return nil }
        let album = Self.dictionary(item["album"])
        let artists = item["singer"] as? [[String: Any]] ?? []
        let artwork = (album["mid"] as? String).flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\($0).jpg") }
        return Track(mediaID: mid, provider: .qq, title: item["title"] as? String ?? item["name"] as? String ?? item["songname"] as? String ?? "歌曲",
            artist: artists.compactMap { $0["name"] as? String }.joined(separator: " / "), album: album["name"] as? String ?? "",
            artworkURL: artwork, duration: item["interval"] as? Double ?? 0)
    }
}
