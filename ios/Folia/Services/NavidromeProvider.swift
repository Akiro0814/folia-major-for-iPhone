import Foundation
// ios/Folia/Services/NavidromeProvider.swift

struct NavidromeConfiguration: Codable, Equatable, Sendable {
    var serverURL: String
    var username: String
    var password: String
}
struct NavidromeArtist: Identifiable, Sendable {
    var id: String
    var name: String
    var albumCount: Int
}

actor NavidromeProvider {
    private let session: URLSession
    private let vault = SessionVault()
    private var configuration: NavidromeConfiguration?
    private var generation = UUID()

    init(session: URLSession = .shared) {
        self.session = session
        if let stored = try? SessionVault().read(.navidrome), let json = stored.cookies["configuration"], let data = json.data(using: .utf8) {
            configuration = try? JSONDecoder().decode(NavidromeConfiguration.self, from: data)
        }
    }
    func account() -> MusicAccount? {
        guard let configuration else { return nil }
        return MusicAccount(id: configuration.username, provider: .navidrome, nickname: configuration.username)
    }
    // Verify credentials before replacing the current Keychain configuration.
    func configure(serverURL: String, username: String, password: String) async throws {
        let candidate = NavidromeConfiguration(serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: password)
        guard !username.isEmpty, !password.isEmpty else { throw MusicError.authenticationRequired }
        let requestGeneration = generation
        _ = try await request("ping", configuration: candidate)
        guard generation == requestGeneration else { throw MusicError.sessionChanged }
        let encoded = try JSONEncoder().encode(candidate)
        try vault.write(ProviderSession(account: MusicAccount(id: username, provider: .navidrome, nickname: username), cookies: ["configuration": String(decoding: encoded, as: UTF8.self)]), provider: .navidrome)
        configuration = candidate; generation = UUID()
    }
    func logout() throws {
        try vault.write(ProviderSession(), provider: .navidrome)
        configuration = nil; generation = UUID()
    }
    func search(_ query: String) async throws -> [Track] {
        let config = try requireConfiguration()
        let root = try await request("search3", parameters: [.init(name: "query", value: query), .init(name: "songCount", value: "100"), .init(name: "artistCount", value: "0"), .init(name: "albumCount", value: "0")])
        let result = root["searchResult3"] as? [String: Any] ?? [:]
        return try songs(result["song"], configuration: config)
    }
    func stream(for track: Track, quality: AudioQuality = .high) throws -> AudioSource {
        guard track.provider == .navidrome else { throw MusicError.invalidResponse }
        var parameters = [URLQueryItem(name: "id", value: track.mediaID)]
        if quality != .lossless { parameters += [.init(name: "format", value: "mp3"), .init(name: "maxBitRate", value: quality == .standard ? "128" : "320")] }
        return AudioSource(url: try Self.url(configuration: requireConfiguration(), endpoint: "stream", parameters: parameters))
    }
    func playlists() async throws -> [MusicCollection] {
        let config = try requireConfiguration()
        let result = try await request("getPlaylists")
        return try collections((result["playlists"] as? [String: Any])?["playlist"], configuration: config)
    }
    func albums(offset: Int = 0) async throws -> [MusicCollection] {
        let config = try requireConfiguration()
        let root = try await request("getAlbumList2", parameters: [.init(name: "type", value: "alphabeticalByName"), .init(name: "size", value: "100"), .init(name: "offset", value: String(max(0, offset)))])
        return try collections((root["albumList2"] as? [String: Any])?["album"], configuration: config, prefix: "album:")
    }
    func artists() async throws -> [NavidromeArtist] {
        let root = try await request("getArtists")
        let indexes = (root["artists"] as? [String: Any])?["index"] as? [[String: Any]] ?? []
        return indexes.flatMap { $0["artist"] as? [[String: Any]] ?? [] }.compactMap { item in
            guard let id = OmniService.identifier(item["id"]) else { return nil }
            return NavidromeArtist(id: id, name: item["name"] as? String ?? "", albumCount: item["albumCount"] as? Int ?? 0)
        }
    }
    func albums(artistID: String) async throws -> [MusicCollection] {
        let config = try requireConfiguration()
        let root = try await request("getArtist", parameters: [.init(name: "id", value: artistID)])
        return try collections((root["artist"] as? [String: Any])?["album"], configuration: config, prefix: "album:")
    }
    func tracks(in collection: MusicCollection) async throws -> [Track] {
        let config = try requireConfiguration()
        let isAlbum = collection.id.hasPrefix("album:")
        let id = isAlbum ? String(collection.id.dropFirst(6)) : collection.id
        let root = try await request(isAlbum ? "getAlbum" : "getPlaylist", parameters: [.init(name: "id", value: id)])
        let detail = root[isAlbum ? "album" : "playlist"] as? [String: Any] ?? [:]
        return try songs(detail[isAlbum ? "song" : "entry"], configuration: config)
    }
    func recommendations() async throws -> [Track] {
        let config = try requireConfiguration()
        let root = try await request("getRandomSongs", parameters: [.init(name: "size", value: "50")])
        return try songs((root["randomSongs"] as? [String: Any])?["song"], configuration: config)
    }
    func setLiked(_ liked: Bool, track: Track) async throws {
        _ = try await request(liked ? "star" : "unstar", parameters: [.init(name: "id", value: track.mediaID)])
    }
    func changePlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard !collection.id.hasPrefix("album:") else { throw MusicError.unsupported("专辑不能作为歌单编辑。") }
        var parameters = [URLQueryItem(name: "playlistId", value: collection.id)]
        if add { parameters.append(.init(name: "songIdToAdd", value: track.mediaID)) }
        else {
            let root = try await request("getPlaylist", parameters: [.init(name: "id", value: collection.id)])
            let entries = (root["playlist"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
            // Subsonic removes entries by zero-based index, not song ID; remove every duplicate.
            parameters += entries.enumerated().compactMap { index, entry in
                OmniService.identifier(entry["id"]) == track.mediaID ? .init(name: "songIndexToRemove", value: String(index)) : nil
            }
            guard parameters.count > 1 else { return }
        }
        _ = try await request("updatePlaylist", parameters: parameters)
    }
    func createPlaylist(name: String) async throws -> MusicCollection {
        let config = try requireConfiguration()
        let root = try await request("createPlaylist", parameters: [.init(name: "name", value: name)])
        guard let item = root["playlist"] as? [String: Any], let result = try collections([item], configuration: config).first else { throw MusicError.invalidResponse }
        return result
    }
    func deletePlaylist(_ collection: MusicCollection) async throws {
        _ = try await request("deletePlaylist", parameters: [.init(name: "id", value: collection.id)])
    }
    func lyrics(for track: Track) async throws -> LyricsPayload {
        do {
            let root = try await request("getLyricsBySongId", parameters: [.init(name: "id", value: track.mediaID), .init(name: "enhanced", value: "true")])
            let entries = (root["lyricsList"] as? [String: Any])?["structuredLyrics"] as? [[String: Any]] ?? []
            if let lyric = entries.first(where: { $0["synced"] as? Bool == true }) ?? entries.first {
                return LyricsPayload(original: Self.lyricText(lyric))
            }
        } catch MusicError.server(let code, _) where [0, 20, 30, 70].contains(code) { /* Older Subsonic servers expose only getLyrics. */ }
        let root = try await request("getLyrics", parameters: [.init(name: "artist", value: track.artist), .init(name: "title", value: track.title)])
        return LyricsPayload(original: (root["lyrics"] as? [String: Any])?["value"] as? String ?? "")
    }
    // Translate OpenSubsonic millisecond line timing into Folia's existing LRC parser contract.
    static func lyricText(_ lyric: [String: Any]) -> String {
        let synced = lyric["synced"] as? Bool == true
        let offset = (lyric["offset"] as? NSNumber)?.doubleValue ?? 0
        return (lyric["line"] as? [[String: Any]] ?? []).map { line in
            let value = line["value"] as? String ?? ""
            guard synced, let start = line["start"] as? NSNumber else { return value }
            let seconds = max(0, (start.doubleValue + offset) / 1000)
            return String(format: "[%02d:%05.2f]", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60)) + value
        }.joined(separator: "\n")
    }
    private func requireConfiguration() throws -> NavidromeConfiguration {
        guard let configuration else { throw MusicError.authenticationRequired }; return configuration
    }
    private func request(_ endpoint: String, parameters: [URLQueryItem] = [], configuration override: NavidromeConfiguration? = nil) async throws -> [String: Any] {
        let config = try override ?? requireConfiguration()
        let revision = generation
        let url = try Self.url(configuration: config, endpoint: endpoint, parameters: parameters)
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard revision == generation else { throw MusicError.sessionChanged }
        guard let http = response as? HTTPURLResponse else { throw MusicError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MusicError.server(http.statusCode, "Navidrome 请求失败") }
        return try Self.decode(data)
    }
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let root = envelope["subsonic-response"] as? [String: Any] else { throw MusicError.invalidResponse }
        guard root["status"] as? String == "ok" else {
            let detail = root["error"] as? [String: Any] ?? [:]
            throw MusicError.server(detail["code"] as? Int ?? 0, detail["message"] as? String ?? "Navidrome 返回错误")
        }
        return root
    }
    static func url(configuration: NavidromeConfiguration, endpoint: String, parameters: [URLQueryItem] = [], salt: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) throws -> URL {
        guard var parts = URLComponents(string: configuration.serverURL), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { throw MusicError.unavailable("请输入有效的 Navidrome HTTP(S) 服务地址，不要包含密码或查询参数。") }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = (parts.path.isEmpty ? "" : "/" + parts.path) + "/rest/" + endpoint
        parts.queryItems = [.init(name: "u", value: configuration.username), .init(name: "t", value: ProtocolCrypto.md5(configuration.password + salt)), .init(name: "s", value: salt), .init(name: "v", value: "1.16.1"), .init(name: "c", value: "Folia"), .init(name: "f", value: "json")] + parameters
        guard let url = parts.url else { throw MusicError.invalidResponse }; return url
    }
    private func songs(_ value: Any?, configuration: NavidromeConfiguration) throws -> [Track] {
        try (value as? [[String: Any]] ?? []).compactMap { item in
            guard let id = OmniService.identifier(item["id"]) else { return nil }
            return Track(mediaID: id, provider: .navidrome, title: item["title"] as? String ?? "", artist: item["artist"] as? String ?? "", album: item["album"] as? String ?? "", artworkURL: try artwork(item, configuration: configuration), duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0)
        }
    }
    private func collections(_ value: Any?, configuration: NavidromeConfiguration, prefix: String = "") throws -> [MusicCollection] {
        try (value as? [[String: Any]] ?? []).compactMap { item in
            guard let id = OmniService.identifier(item["id"]) else { return nil }
            return MusicCollection(id: prefix + id, provider: .navidrome, title: item["name"] as? String ?? "", artworkURL: try artwork(item, configuration: configuration), trackCount: item["songCount"] as? Int ?? 0)
        }
    }
    private func artwork(_ item: [String: Any], configuration: NavidromeConfiguration) throws -> URL? {
        guard let id = item["coverArt"] as? String else { return nil }
        return try Self.url(configuration: configuration, endpoint: "getCoverArt", parameters: [.init(name: "id", value: id), .init(name: "size", value: "600")])
    }
}
