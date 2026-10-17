import Foundation
// ios/Folia/Services/BodianCatalog.swift

extension BodianProvider {
    // The upstream exposes song search, not album/artist search: discover actual catalog references in matching songs.
    func searchCatalog(_ query: String, kind: CatalogKind) async throws -> [MusicCollection] {
        let songs = try await search(query)
        var seen = Set<String>()
        return songs.compactMap { song in
            guard let id = song.providerData[kind == .album ? "albumId" : "artistId"],
                  (try? Self.mediaID(id)) != nil, seen.insert(id).inserted else { return nil }
            return MusicCollection(id: id, provider: .bodian, title: kind == .album ? song.album : song.artist,
                                   artworkURL: song.artworkURL, providerData: ["kind": kind.rawValue, "source": kind == .album ? "6" : "4"])
        }
    }
    func catalogTracks(_ collection: MusicCollection, kind: CatalogKind) async throws -> [Track] {
        guard collection.provider == .bodian else { throw MusicError.invalidResponse }
        _ = try Self.mediaID(collection.id)
        var songs: [Track] = []
        for page in 0..<1000 {
            let root = try await data("/api/service/\(kind == .album ? "album" : "artist")/music/\(collection.id)", fields: [("pn", String(page)), ("rn", "100")])
            guard let entries = root["resultList"] as? [[String: Any]] else { throw MusicError.invalidResponse }
            songs += entries.compactMap(Self.normalize)
            let total = Self.number(root["total"])
            if entries.isEmpty || (total.map { (page + 1) * 100 >= $0 } ?? (entries.count < 100)) { break }
            try Task.checkCancellation()
        }
        return songs
    }
}
