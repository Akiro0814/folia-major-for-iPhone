import XCTest
@testable import Folia

// FoliaTests/AppBackupTests.swift — backup restores references only and excludes session-bearing media metadata.
final class AppBackupTests: XCTestCase {
    func testUnsupportedSchemaAndLocalProviderAreRejected() throws {
        var backup = FoliaBackup()
        backup.schemaVersion = 2
        XCTAssertThrowsError(try backup.validated())
        let data = Data(#"{"mediaID":"file:///song.mp3","provider":"local","title":"Local","artist":"","album":"","duration":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Track.self, from: data))
    }
    func testBackupExportRemovesSignedArtworkAndCredentials() throws {
        let track = Track(mediaID: "42", provider: .navidrome, title: "Song", artist: "Artist", artworkURL: URL(string: "https://music.example/rest/getCoverArt?t=SECRET&s=salt"), providerData: ["serverNamespace": "abc", "token": "SECRET"])
        let reference = FoliaBackup.reference(track)
        XCTAssertNil(reference.artworkURL)
        XCTAssertEqual(reference.providerData, ["serverNamespace": "abc"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(reference), as: UTF8.self).contains("SECRET"))
    }
    func testQueueIndexAndPositionMustBeBounded() {
        var queue = PlaybackSnapshot()
        queue.index = 3
        XCTAssertThrowsError(try queue.validated())
        queue.index = nil; queue.position = .infinity
        XCTAssertThrowsError(try queue.validated())
    }
    func testOlderTrackWithoutProviderMetadataDecodes() throws {
        let data = Data(#"{"mediaID":"42","provider":"netease","title":"Song","artist":"Artist","duration":3}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Track.self, from: data).providerData.isEmpty)
    }
}
