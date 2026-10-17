import Foundation
// ios/Folia/Services/QQAlbumArtist.swift

extension QQProvider {
    func searchCatalog(_ query: String, kind: CatalogKind) async throws -> [MusicCollection] {
        let result = try await call("music.search.SearchCgiService", "DoSearchForQQMusicLite", ["search_id": String(UInt64.random(in: 100000000000000000...999999999999999999)),
            "remoteplace": "search.android.keyboard", "query": query, "search_type": kind == .album ? 2 : 1, "num_per_page": 20, "page_num": 1,
            "highlight": 0, "nqc_flag": 0, "page_id": 1, "grp": 1], auth: session.account != nil)
        if let code = result["code"] as? Int, code != 0 { throw MusicError.server(code, "QQ 音乐搜索失败") }
        let key = kind == .album ? "item_album" : "singer"
        let items = Self.dictionary(result["body"])[key] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["mid"] as? String ?? item["albumMID"] as? String ?? item["singerMID"] as? String else { return nil }
            let title = item["name"] as? String ?? item["albumName"] as? String ?? item["singerName"] as? String ?? ""
            let code = kind == .album ? "T002" : "T001"
            return MusicCollection(id: id, provider: .qq, title: title,
                artworkURL: URL(string: "https://y.gtimg.cn/music/photo_new/\(code)R500x500M000\(id).jpg"), providerData: ["kind": kind.rawValue])
        }
    }
    func catalogTracks(_ collection: MusicCollection, kind: CatalogKind) async throws -> [Track] {
        if kind == .album {
            var url = URLComponents(string: "https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg")!
            url.queryItems = [URLQueryItem(name: "albummid", value: collection.id), URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "outCharset", value: "utf-8")]
            var request = URLRequest(url: url.url!)
            request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
            let result = try await json(request)
            guard result["code"] as? Int == 0 else { throw MusicError.server(result["code"] as? Int ?? -1, "QQ 音乐专辑读取失败") }
            return (Self.dictionary(result["data"])["list"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
        }
        var tracks: [Track] = [], seen = Set<String>()
        while true {
            let result = try await call("music.web_singer_info_svr", "get_singer_detail_info", ["sort": 5,
                "singermid": collection.id, "sin": tracks.count, "num": 100], auth: session.account != nil, overrides: ["ct": 24, "cv": 0])
            let page = (result["songlist"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
            let fresh = page.filter { seen.insert($0.mediaID).inserted }
            tracks += fresh
            if fresh.isEmpty || page.count < 100 { break }
            if let total = result["total_song"] as? Int, tracks.count >= total { break }
            try Task.checkCancellation()
        }
        return tracks
    }
}
