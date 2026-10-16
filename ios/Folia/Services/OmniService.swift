import Foundation
// ios/Folia/Services/OmniService.swift

actor OmniService {
    let netease = NeteaseTransport()
    let discovery = PublicDiscoveryTransport()
    func loginMethods(provider: MusicProvider) -> [LoginMethod] { provider == .netease ? [.sms, .password, .qr] : [] }
    func account(provider: MusicProvider) async -> MusicAccount? {
        provider == .netease ? await netease.account() : nil
    }
    func logout(provider: MusicProvider) async throws {
        if provider == .netease { try await netease.logout() }
    }
    func search(_ query: String, provider: MusicProvider) async throws -> [Track] {
        if provider != .netease { return try await discovery.search(query, provider: provider) }
        let result = try await netease.request("/api/search/get", ["s": query, "type": 1, "limit": 50, "offset": 0])
        let songs = (result["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        return songs.compactMap(Self.normalizeNetease)
    }
    func stream(for track: Track, quality: AudioQuality = .high) async throws -> AudioSource {
        if track.provider != .netease { return try await discovery.stream(track, quality: quality) }
        let bitrate = quality == .standard ? 128000 : quality == .high ? 320000 : 999000
        let result = try await netease.request("/api/song/enhance/player/url", ["ids": "[\(track.mediaID)]", "br": bitrate])
        guard let entry = (result["data"] as? [[String: Any]])?.first,
              let value = entry["url"] as? String, let url = URL(string: value), ["https", "http"].contains(url.scheme ?? "") else {
            throw MusicError.unavailable("此歌曲暂无可播放地址，可能需要会员或受版权区域限制。")
        }
        return AudioSource(url: url, expiresAt: Date().addingTimeInterval((entry["expi"] as? Double) ?? 600))
    }
    func lyrics(for track: Track) async throws -> LyricsPayload {
        if track.provider != .netease { return try await discovery.lyrics(track) }
        let result = try await netease.request("/api/song/lyric", ["id": track.mediaID, "tv": -1, "lv": -1, "rv": -1, "kv": -1, "_nmclfl": 1])
        return LyricsPayload(original: Self.lyricField(result, "lrc"), translation: Self.lyricField(result, "tlyric"),
                             romanization: Self.lyricField(result, "romalrc"), wordTimed: Self.lyricField(result, "yrc"))
    }
    func playlists(provider: MusicProvider) async throws -> [MusicCollection] {
        try requireNetease(provider)
        guard let user = await netease.account() else { throw MusicError.authenticationRequired }
        let result = try await netease.request("/api/user/playlist", ["uid": user.id, "limit": 1000, "offset": 0, "includeVideo": true])
        return (result["playlist"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = Self.identifier(item["id"]) else { return nil }
            return MusicCollection(id: id, provider: .netease, title: item["name"] as? String ?? "歌单",
                artworkURL: (item["coverImgUrl"] as? String).flatMap(URL.init(string:)), trackCount: item["trackCount"] as? Int ?? 0)
        }
    }
    func tracks(in collection: MusicCollection) async throws -> [Track] {
        try requireNetease(collection.provider)
        let result = try await netease.request("/api/v6/playlist/detail", ["id": collection.id, "n": 100000, "s": 8])
        guard let playlist = result["playlist"] as? [String: Any] else { throw MusicError.invalidResponse }
        let ids = (playlist["trackIds"] as? [[String: Any]] ?? []).compactMap { Self.identifier($0["id"]) }
        if ids.isEmpty { return (playlist["tracks"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease) }
        var songs: [Track] = []
        for start in stride(from: 0, to: ids.count, by: 200) {
            try Task.checkCancellation()
            let chunk = ids[start..<min(start + 200, ids.count)].map { ["id": $0] }
            let encoded = try JSONSerialization.data(withJSONObject: chunk)
            let details = try await netease.request("/api/v3/song/detail", ["c": String(decoding: encoded, as: UTF8.self)])
            songs += (details["songs"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease)
        }
        let map = Dictionary(songs.map { ($0.mediaID, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { map[$0] }
    }
    func setLiked(_ liked: Bool, track: Track) async throws {
        try requireNetease(track.provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        _ = try await netease.request("/api/radio/like", ["trackId": track.mediaID, "like": liked, "alg": "itembased", "time": 3])
    }
    func changePlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard collection.provider == track.provider else { throw MusicError.unsupported("歌曲与歌单必须来自同一音乐平台。") }
        try requireNetease(track.provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        let ids = try JSONSerialization.data(withJSONObject: [track.mediaID])
        _ = try await netease.request("/api/playlist/manipulate/tracks", ["op": add ? "add" : "del", "pid": collection.id,
            "trackIds": String(decoding: ids, as: UTF8.self), "imme": "true"])
    }
    func recommendations(provider: MusicProvider) async throws -> [Track] {
        try requireNetease(provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        let result = try await netease.request("/api/v3/discovery/recommend/songs")
        return ((result["data"] as? [String: Any])?["dailySongs"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease)
    }
    func requireNetease(_ provider: MusicProvider) throws {
        guard provider == .netease else { throw MusicError.unsupported("\(provider.title) 的设备端授权及播放协议尚未完成，不能使用托管 API 代替。") }
    }
    static func identifier(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
    static func normalizeNetease(_ item: [String: Any]) -> Track? {
        guard let id = identifier(item["id"]) else { return nil }
        let album = item["al"] as? [String: Any] ?? item["album"] as? [String: Any] ?? [:]
        let artists = item["ar"] as? [[String: Any]] ?? item["artists"] as? [[String: Any]] ?? []
        return Track(mediaID: id, provider: .netease, title: item["name"] as? String ?? "未命名歌曲",
            artist: artists.compactMap { $0["name"] as? String }.joined(separator: " / "), album: album["name"] as? String ?? "",
            artworkURL: (album["picUrl"] as? String).flatMap(URL.init(string:)),
            duration: ((item["dt"] as? Double) ?? (item["duration"] as? Double) ?? 0) / 1000)
    }
    private static func lyricField(_ result: [String: Any], _ field: String) -> String {
        (result[field] as? [String: Any])?["lyric"] as? String ?? ""
    }
}

