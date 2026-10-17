import Foundation
// ios/Folia/Services/OmniCatalog.swift

extension OmniService {
    func searchCatalog(_ query: String, provider: MusicProvider, kind: CatalogKind) async throws -> [MusicCollection] {
        if provider == .bodian { return try await bodian.searchCatalog(query, kind: kind) }
        if provider == .navidrome { return try await navidrome.searchCatalog(query, kind: kind) }
        if provider == .qq { return try await qq.searchCatalog(query, kind: kind) }
        if provider == .kugou { return try await discovery.kugouSearchCatalog(query, kind: kind) }
        try requireNetease(provider)
        let result = try await netease.request("/api/search/get", ["s": query, "type": kind == .album ? 10 : 100, "limit": 100, "offset": 0])
        let group = result["result"] as? [String: Any] ?? [:]
        let items = group[kind == .album ? "albums" : "artists"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = Self.identifier(item["id"]) else { return nil }
            return MusicCollection(id: id, provider: .netease, title: item["name"] as? String ?? "",
                artworkURL: (item["picUrl"] as? String ?? item["img1v1Url"] as? String).flatMap(URL.init(string:)),
                trackCount: item["size"] as? Int ?? item["musicSize"] as? Int ?? 0, providerData: ["kind": kind.rawValue])
        }
    }
    func catalogTracks(in collection: MusicCollection, kind: CatalogKind) async throws -> [Track] {
        if collection.provider == .bodian { return try await bodian.catalogTracks(collection, kind: kind) }
        if collection.provider == .navidrome { return try await navidrome.catalogTracks(collection, kind: kind) }
        if collection.provider == .qq { return try await qq.catalogTracks(collection, kind: kind) }
        if collection.provider == .kugou { return try await discovery.kugouCatalogTracks(collection, kind: kind) }
        try requireNetease(collection.provider)
        if kind == .album {
            let result = try await netease.request("/api/v1/album/\(collection.id)")
            return (result["songs"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease)
        }
        var tracks: [Track] = [], seen = Set<String>()
        while true {
            let result = try await netease.request("/api/v1/artist/songs", ["id": collection.id, "private_cloud": "true",
                "work_type": 1, "order": "hot", "offset": tracks.count, "limit": 100])
            let page = (result["songs"] as? [[String: Any]] ?? []).compactMap(Self.normalizeNetease)
            let fresh = page.filter { seen.insert($0.mediaID).inserted }
            tracks += fresh
            if result["more"] as? Bool != true || fresh.isEmpty { break }
            try Task.checkCancellation()
        }
        return tracks
    }
}
