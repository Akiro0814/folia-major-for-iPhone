import Foundation
// ios/Folia/Domain/MusicModelDecoding.swift

extension Track {
    enum CodingKeys: String, CodingKey { case mediaID, provider, title, artist, album, artworkURL, duration, providerData }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try data.decode(String.self, forKey: .mediaID)
        provider = try data.decode(MusicProvider.self, forKey: .provider)
        title = try data.decode(String.self, forKey: .title)
        artist = try data.decode(String.self, forKey: .artist)
        album = try data.decodeIfPresent(String.self, forKey: .album) ?? ""
        artworkURL = try data.decodeIfPresent(URL.self, forKey: .artworkURL)
        duration = try data.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        providerData = try data.decodeIfPresent([String: String].self, forKey: .providerData) ?? [:]
    }
}
extension MusicCollection {
    enum CodingKeys: String, CodingKey { case id, provider, title, artworkURL, trackCount, providerData }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(String.self, forKey: .id)
        provider = try data.decode(MusicProvider.self, forKey: .provider)
        title = try data.decode(String.self, forKey: .title)
        artworkURL = try data.decodeIfPresent(URL.self, forKey: .artworkURL)
        trackCount = try data.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        providerData = try data.decodeIfPresent([String: String].self, forKey: .providerData) ?? [:]
    }
}
