import Foundation
// ios/Folia/Services/OmniArtwork.swift

extension OmniService {
    func resolveArtworkURL(_ url: URL) async throws -> URL {
        if url.scheme == "folia-navidrome" { return try await navidrome.resolveArtwork(reference: url) }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { throw MusicError.invalidResponse }
        return url
    }
}
