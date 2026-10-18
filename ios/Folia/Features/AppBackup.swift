import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Folia/Features/AppBackup.swift — versioned portable app state without audio files or account credentials.
struct PlaybackSnapshot: Codable {
    var tracks: [Track] = []
    var index: Int?
    var position: Double = 0
    var repeatMode: RepeatMode = .off
    var shuffle = false
    var quality: AudioQuality = .high

    func validated() throws -> PlaybackSnapshot {
        guard tracks.count <= 10_000, position.isFinite, (0...604_800).contains(position),
              index == nil || tracks.indices.contains(index!) else { throw CocoaError(.fileReadCorruptFile) }
        try tracks.forEach(FoliaBackup.validateReference)
        return self
    }
}

struct FoliaBackup: Codable {
    var schemaVersion = 1
    var visual = VisualSettings()
    var palettes: [SavedPalette] = []
    var favorites: [Track] = []
    var playback = PlaybackSnapshot()
    var preferredProvider: MusicProvider = .netease

    func validated() throws -> FoliaBackup {
        guard schemaVersion == 1, palettes.count <= 100, favorites.count <= 10_000,
              Set(palettes.map(\.id)).count == palettes.count else { throw CocoaError(.fileReadCorruptFile) }
        _ = try visual.validated()
        _ = try playback.validated()
        for palette in palettes {
            guard !palette.name.isEmpty, palette.name.count <= 80 else { throw CocoaError(.fileReadCorruptFile) }
            _ = try AIThemeService.validate(palette.colors)
        }
        try favorites.forEach(Self.validateReference)
        return self
    }
    static let referenceKeys: Set<String> = ["serverNamespace", "albumID", "mixsongID", "fileID", "albumId", "artistId"]

    // Export stable media identifiers, never transient playback signatures or authenticated artwork URLs.
    static func reference(_ track: Track) -> Track {
        var result = track
        result.providerData = track.providerData.filter { referenceKeys.contains($0.key) }
        if let url = result.artworkURL, !safeArtwork(url) { result.artworkURL = nil }
        return result
    }
    static func validateReference(_ track: Track) throws {
        guard !track.mediaID.isEmpty, track.mediaID.count <= 512, !track.mediaID.contains("://"),
              !track.mediaID.hasPrefix("/"), !track.mediaID.hasPrefix("\\"),
              track.mediaID.range(of: "^[A-Za-z]:[\\\\/]", options: .regularExpression) == nil,
              track.title.count <= 2048, track.artist.count <= 2048, track.album.count <= 2048,
              track.duration.isFinite, (0...604_800).contains(track.duration),
              track.providerData.keys.allSatisfy(referenceKeys.contains),
              track.providerData.values.allSatisfy({ $0.count <= 512 }),
              track.artworkURL.map(safeArtwork) != false else { throw CocoaError(.fileReadCorruptFile) }
    }
    private static func safeArtwork(_ url: URL) -> Bool {
        if url.scheme == "folia-navidrome", url.host == "cover", url.user == nil, url.password == nil,
           let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let query = parts.queryItems {
            return query.count == 2 && Set(query.map(\.name)) == Set(["id", "serverNamespace"])
                && query.allSatisfy { !($0.value ?? "").isEmpty && ($0.value?.count ?? 0) <= 512 }
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let secrets: Set<String> = ["t", "s", "u", "key", "token", "access_token", "auth", "password", "signature", "sign"]
        return parts.queryItems?.allSatisfy { !secrets.contains($0.name.lowercased()) } != false
    }
}

struct FoliaBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var backup: FoliaBackup
    init(backup: FoliaBackup) { self.backup = backup }
    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        guard data.count <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        backup = try JSONDecoder().decode(FoliaBackup.self, from: data).validated()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        _ = try backup.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}

