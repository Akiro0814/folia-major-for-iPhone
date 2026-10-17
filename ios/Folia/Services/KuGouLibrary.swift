import Foundation
// ios/Folia/Services/KuGouLibrary.swift

extension PublicDiscoveryTransport {
    func kugouPlaylists() async throws -> [MusicCollection] {
        guard let user = kugouSession.account, let token = kugouSession.cookies["token"] else { throw MusicError.authenticationRequired }
        var result: [MusicCollection] = [], page = 1
        var seen = Set<String>()
        while true {
            let response = try await kugou("/v7/get_all_list", params: ["plat": "1", "userid": user.id, "token": token],
                router: "cloudlist.service.kugou.com", body: ["userid": user.id, "token": token, "total_ver": 979,
                    "type": 2, "page": page, "pagesize": 100])
            let items = Self.kugouItems(response)
            var fresh = 0
            for item in items {
                guard let listID = OmniService.identifier(item["listid"]), seen.insert(listID).inserted else { continue }
                let globalID = OmniService.identifier(item["global_collection_id"])
                let image = (item["pic"] as? String ?? item["img"] as? String)?.replacingOccurrences(of: "{size}", with: "480")
                result.append(MusicCollection(id: globalID ?? listID, provider: .kugou,
                    title: item["name"] as? String ?? item["listname"] as? String ?? "歌单", artworkURL: image.flatMap(URL.init(string:)),
                    trackCount: item["count"] as? Int ?? item["songcount"] as? Int ?? 0,
                    providerData: ["listid": listID, "globalID": globalID ?? "", "owner": OmniService.identifier(item["create_userid"]) ?? user.id]))
                fresh += 1
            }
            if items.count < 100 || fresh == 0 { break }
            page += 1
            try Task.checkCancellation()
        }
        return result
    }
    func kugouTracks(in collection: MusicCollection) async throws -> [Track] {
        guard let listID = collection.providerData["listid"] else { throw MusicError.invalidResponse }
        guard let user = kugouSession.account, let token = kugouSession.cookies["token"] else { throw MusicError.authenticationRequired }
        var songs: [Track] = [], page = 1
        var seen = Set<String>()
        while true {
            let response = try await kugou("/v4/get_list_all_file", params: [:], router: "cloudlist.service.kugou.com", body: [
                "listid": listID, "userid": user.id, "area_code": 1, "show_relate_goods": 0, "pagesize": 100,
                "allplatform": 1, "show_cover": 1, "type": 0, "token": token, "page": page])
            let items = Self.kugouItems(response)
            let fresh = items.compactMap(Self.normalizeKugou).filter { seen.insert($0.mediaID).inserted }
            songs += fresh
            if items.count < 100 || fresh.isEmpty { break }
            page += 1
            try Task.checkCancellation()
        }
        return songs
    }
    func kugouRecommendations() async throws -> [Track] {
        guard kugouSession.account != nil else { throw MusicError.authenticationRequired }
        let response = try await kugou("/everyday_song_recommend", params: ["platform": "ios"], router: "everydayrec.service.kugou.com", body: [:])
        return Self.kugouItems(response).compactMap(Self.normalizeKugou)
    }
    func setKugouLiked(_ liked: Bool, track: Track) async throws {
        let lists = try await kugouPlaylists()
        guard let list = lists.first(where: { $0.providerData["listid"] == "2" || ["我喜欢", "我喜欢的音乐"].contains($0.title) }) else { throw MusicError.unavailable("账户未返回我喜欢歌单。") }
        try await changeKugouPlaylist(list, track: track, add: liked)
    }
    func changeKugouPlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard collection.provider == .kugou, track.provider == .kugou, let user = kugouSession.account,
              let token = kugouSession.cookies["token"] else { throw MusicError.authenticationRequired }
        guard collection.providerData["owner"] == user.id, let list = collection.providerData["listid"] else {
            throw MusicError.unsupported("只能修改自己创建的酷狗歌单。")
        }
        if add {
            let resource: [String: Any] = ["number": 1, "name": "\(track.artist) - \(track.title)", "hash": track.mediaID,
                "size": 0, "sort": 0, "timelen": Int(track.duration * 1000), "bitrate": 0,
                "album_id": Int(track.providerData["albumID"] ?? "0") ?? 0, "mixsongid": Int(track.providerData["mixsongID"] ?? "0") ?? 0]
            _ = try await kugou("/cloudlist.service/v6/add_song", params: ["last_time": String(Int(Date().timeIntervalSince1970)), "last_area": "gztx", "userid": user.id, "token": token], body: [
                "userid": user.id, "token": token, "listid": list, "list_ver": 0, "type": 0, "slow_upload": 1, "scene": "false;null", "data": [resource]])
        } else {
            let songs = try await kugouTracks(in: collection)
            guard let stored = songs.first(where: { $0.mediaID.lowercased() == track.mediaID.lowercased() }), let file = stored.providerData["fileID"], let fileID = Int64(file) else { return }
            _ = try await kugou("/v4/delete_songs", params: [:], router: "cloudlist.service.kugou.com", body: [
                "listid": list, "userid": user.id, "data": [["fileid": fileID]], "type": 0, "token": token, "list_ver": 0])
        }
    }
    nonisolated static func kugouItems(_ raw: [String: Any]) -> [[String: Any]] {
        var queue: [Any] = [raw["data"] ?? raw]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let items = current as? [[String: Any]] { return items }
            if let dict = current as? [String: Any] {
                for key in ["lists", "list", "info", "songs", "song_list", "songlist", "songList", "audios", "items", "records", "data", "result", "response"] {
                    if let value = dict[key] { queue.append(value) }
                }
            }
        }
        return []
    }
    nonisolated static func normalizeKugou(_ item: [String: Any]) -> Track? {
        let audio = item["audio_info"] as? [String: Any] ?? [:]
        guard let hash = item["hash"] as? String ?? item["FileHash"] as? String ?? audio["hash"] as? String else { return nil }
        let title = item["songname"] as? String ?? item["SongName"] as? String ?? item["filename"] as? String ?? item["name"] as? String ?? "歌曲"
        let artist = item["singername"] as? String ?? item["SingerName"] as? String ?? ""
        let image = (item["Image"] as? String ?? item["album_sizable_cover"] as? String)?.replacingOccurrences(of: "{size}", with: "480")
        var metadata: [String: String] = [:]
        metadata["fileID"] = OmniService.identifier(item["fileid"] ?? item["FileID"])
        metadata["albumID"] = OmniService.identifier(item["album_id"] ?? item["AlbumID"])
        metadata["mixsongID"] = OmniService.identifier(item["mixsongid"] ?? item["MixSongID"])
        return Track(mediaID: hash, provider: .kugou, title: title, artist: artist,
            album: item["album_name"] as? String ?? item["AlbumName"] as? String ?? "", artworkURL: image.flatMap(URL.init(string:)),
            duration: item["duration"] as? Double ?? (item["timelen"] as? Double ?? 0) / 1000, providerData: metadata)
    }
}
