import Foundation
// ios/Folia/Services/OmniService.swift

actor OmniService {
    let netease = NeteaseTransport()
    let discovery = PublicDiscoveryTransport()
    let navidrome = NavidromeProvider()
    let qq = QQProvider()
    let bodian = BodianProvider()
    func loginMethods(provider: MusicProvider) -> [LoginMethod] { [MusicProvider.qq, .bodian].contains(provider) ? [.qr] : [MusicProvider.netease, .kugou].contains(provider) ? [.sms, .password, .qr] : [] }
    func account(provider: MusicProvider) async -> MusicAccount? {
        if provider == .bodian { return await bodian.account() }
        if provider == .qq { return await qq.account() }
        if provider == .navidrome { return await navidrome.account() }
        if provider == .kugou { return await discovery.kugouAccount() }
        return provider == .netease ? await netease.account() : nil
    }
    func logout(provider: MusicProvider) async throws {
        if provider == .bodian { try await bodian.logout(); return }
        if provider == .qq { try await qq.logout(); return }
        if provider == .navidrome { try await navidrome.logout(); return }
        if provider == .kugou { try await discovery.logoutKugou(); return }
        if provider == .netease { try await netease.logout() }
    }
    func search(_ query: String, provider: MusicProvider) async throws -> [Track] {
        if provider == .bodian { return try await bodian.search(query) }
        if provider == .qq, await qq.account() != nil { return try await qq.search(query) }
        if provider == .navidrome { return try await navidrome.search(query) }
        if provider != .netease { return try await discovery.search(query, provider: provider) }
        let result = try await netease.request("/api/search/get", ["s": query, "type": 1, "limit": 50, "offset": 0])
        let songs = (result["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        return songs.compactMap(Self.normalizeNetease)
    }
    func stream(for track: Track, quality: AudioQuality = .high) async throws -> AudioSource {
        if track.provider == .bodian { return try await bodian.stream(for: track, quality: quality) }
        if track.provider == .qq { return try await qq.stream(for: track, quality: quality) }
        if track.provider == .navidrome { return try await navidrome.stream(for: track, quality: quality) }
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
        if track.provider == .bodian { return try await bodian.lyrics(for: track) }
        if track.provider == .qq { return try await qq.lyrics(for: track) }
        if track.provider == .navidrome { return try await navidrome.lyrics(for: track) }
        if track.provider != .netease { return try await discovery.lyrics(track) }
        let result = try await netease.request("/api/song/lyric/v1", ["id": track.mediaID, "cp": false, "tv": 0, "lv": 0, "rv": 0, "kv": 0, "yv": 0, "ytv": 0, "yrv": 0])
        return LyricsPayload(original: Self.lyricField(result, "lrc"), translation: Self.lyricField(result, "tlyric"),
                             romanization: Self.lyricField(result, "romalrc"), wordTimed: Self.lyricField(result, "yrc"))
    }
    func playlists(provider: MusicProvider) async throws -> [MusicCollection] {
        if provider == .kugou { return try await discovery.kugouPlaylists() }
        if provider == .bodian { return try await bodian.playlists() }
        if provider == .qq { return try await qq.playlists() }
        if provider == .navidrome { return try await navidrome.playlists() }
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
        if let raw = collection.providerData["kind"], let kind = CatalogKind(rawValue: raw) {
            return try await catalogTracks(in: collection, kind: kind)
        }
        if collection.provider == .kugou { return try await discovery.kugouTracks(in: collection) }
        if collection.provider == .bodian { return try await bodian.tracks(in: collection) }
        if collection.provider == .qq { return try await qq.tracks(in: collection) }
        if collection.provider == .navidrome { return try await navidrome.tracks(in: collection) }
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
        if track.provider == .kugou { try await discovery.setKugouLiked(liked, track: track); return }
        if track.provider == .bodian { try await bodian.setLiked(liked, track: track); return }
        if track.provider == .qq { try await qq.setLiked(liked, track: track); return }
        if track.provider == .navidrome { try await navidrome.setLiked(liked, track: track); return }
        try requireNetease(track.provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        _ = try await netease.request("/api/radio/like", ["trackId": track.mediaID, "like": liked, "alg": "itembased", "time": 3])
    }
    func changePlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard collection.provider == track.provider else { throw MusicError.unsupported("歌曲与歌单必须来自同一音乐平台。") }
        if collection.provider == .kugou { try await discovery.changeKugouPlaylist(collection, track: track, add: add); return }
        if collection.provider == .bodian { try await bodian.changePlaylist(collection, track: track, add: add); return }
        if collection.provider == .qq { try await qq.changePlaylist(collection, track: track, add: add); return }
        if collection.provider == .navidrome { try await navidrome.changePlaylist(collection, track: track, add: add); return }
        try requireNetease(track.provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        let ids = try JSONSerialization.data(withJSONObject: [track.mediaID])
        _ = try await netease.request("/api/playlist/manipulate/tracks", ["op": add ? "add" : "del", "pid": collection.id,
            "trackIds": String(decoding: ids, as: UTF8.self), "imme": "true"])
    }
    func recommendations(provider: MusicProvider) async throws -> [Track] {
        if provider == .kugou { return try await discovery.kugouRecommendations() }
        if provider == .bodian { return try await bodian.recommendations() }
        if provider == .qq { return try await qq.recommendations() }
        if provider == .navidrome { return try await navidrome.recommendations() }
        try requireNetease(provider)
        guard await netease.account() != nil else { throw MusicError.authenticationRequired }
        let result = try await netease.request("/api/v3/discovery/recommend/songs")
        return ((result["data"] as? [String: Any])?["dailySongs"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease)
    }
    func requireNetease(_ provider: MusicProvider) throws {
        guard provider == .netease else { throw MusicError.unsupported("\(provider.title) 不支持当前所选操作。") }
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









