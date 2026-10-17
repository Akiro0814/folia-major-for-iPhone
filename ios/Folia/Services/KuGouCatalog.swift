import Foundation
// ios/Folia/Services/KuGouCatalog.swift

extension PublicDiscoveryTransport {
    func kugouSearchCatalog(_ query: String, kind: CatalogKind) async throws -> [MusicCollection] {
        let type = kind == .album ? "album" : "author"
        let response = try await kugou("/v1/search/\(type)", params: ["albumhide": "0", "iscorrection": "1", "keyword": query,
            "nocollect": "0", "page": "1", "pagesize": "50", "platform": "AndroidFilter"], router: "complexsearch.kugou.com")
        return Self.kugouItems(response).compactMap { item in
            let rawID = kind == .album ? item["AlbumID"] ?? item["album_id"] : item["AuthorId"] ?? item["author_id"] ?? item["SingerId"]
            guard let id = OmniService.identifier(rawID) else { return nil }
            let name = item["AlbumName"] as? String ?? item["album_name"] as? String ?? item["AuthorName"] as? String ?? item["SingerName"] as? String ?? ""
            let image = (item["Img"] as? String ?? item["SizableCover"] as? String ?? item["Avatar"] as? String)?.replacingOccurrences(of: "{size}", with: "480")
            return MusicCollection(id: id, provider: .kugou, title: name, artworkURL: image.flatMap(URL.init(string:)), providerData: ["kind": kind.rawValue])
        }
    }
    func kugouCatalogTracks(_ collection: MusicCollection, kind: CatalogKind) async throws -> [Track] {
        var tracks: [Track] = [], seen = Set<String>(), page = 1
        while true {
            let response: [String: Any]
            if kind == .album {
                response = try await kugou("/v1/album_audio/lite", params: [:], router: "openapi.kugou.com",
                    body: ["album_id": collection.id, "is_buy": "", "page": page, "pagesize": 100], extraHeaders: ["kg-tid": "255"])
            } else {
                let time = Int(Date().timeIntervalSince1970)
                response = try await kugou("/kmr/v1/audio_group/author", params: [:], router: "openapi.kugou.com", base: "https://openapi.kugou.com",
                    body: ["appid": 1005, "clientver": 20489, "mid": deviceMID(), "clienttime": time,
                        "key": ProtocolCrypto.md5("1005OIlwieks28dk2k092lksi2UIkp20489\(time)"), "author_id": collection.id,
                        "pagesize": 100, "page": page, "sort": 1, "area_code": "all"], extraHeaders: ["kg-tid": "220"])
            }
            let raw = Self.kugouItems(response)
            let fresh = raw.compactMap(Self.normalizeKugou).filter { seen.insert($0.mediaID).inserted }
            tracks += fresh
            if raw.count < 100 || fresh.isEmpty { break }
            page += 1
            try Task.checkCancellation()
        }
        return tracks
    }
}
