import Foundation
// ios/Folia/Services/OmniBrowsing.swift

extension OmniService {
    func browseAlbums(provider: MusicProvider, offset: Int = 0, artistID: String? = nil) async throws -> [MusicCollection] {
        guard provider == .navidrome else { throw MusicError.unsupported("此平台的专辑浏览尚未接入。") }
        if let artistID { return try await navidrome.albums(artistID: artistID) }
        return try await navidrome.albums(offset: offset)
    }
    func browseArtists(provider: MusicProvider) async throws -> [NavidromeArtist] {
        guard provider == .navidrome else { throw MusicError.unsupported("此平台的歌手浏览尚未接入。") }
        return try await navidrome.artists()
    }
}
