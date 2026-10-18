import XCTest
@testable import Folia
// ios/FoliaTests/ProviderTests.swift

final class ProviderTests: XCTestCase {
    func testSourceIdentityNeverCollides() {
        let a = Track(mediaID: "123", provider: .netease, title: "Song", artist: "Artist")
        let b = Track(mediaID: "123", provider: .kugou, title: "Song", artist: "Artist")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(Set([a, b]).count, 2)
    }
    func testKuGouObservedSearchFieldsPreserveTitleAndDuration() {
        let song = PublicDiscoveryTransport.normalizeKugou(["FileHash": "abcdef", "OriSongName": "Title", "SingerName": "Artist", "Duration": 180, "MixSongID": 123, "AlbumID": 456])
        XCTAssertEqual(song?.title, "Title")
        XCTAssertEqual(song?.duration, 180)
        XCTAssertEqual(song?.providerData["mixsongID"], "123")
    }
    func testKuGouObservedAlbumNestedAudioShape() {
        let item: [String: Any] = ["audio_info": ["hash": "abc", "duration": 271151],
            "base": ["album_id": 960399, "author_name": "Artist", "audio_name": "Title", "album_audio_id": 32042818],
            "album_info": ["album_name": "Album", "cover": "https://example.com/{size}/cover.jpg"]]
        let track = PublicDiscoveryTransport.normalizeKugou(item)
        XCTAssertEqual(track?.title, "Title")
        XCTAssertEqual(track?.album, "Album")
        XCTAssertEqual(track?.duration ?? 0, 271.151, accuracy: 0.001)
        XCTAssertEqual(track?.providerData["mixsongID"], "32042818")
    }
    func testKuGouJSONNumbersAndFractionalDuration() throws {
        let json = Data(#"{"FileHash":"abc","Duration":180,"OriSongName":"Title"}"#.utf8)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(PublicDiscoveryTransport.normalizeKugou(decoded)?.duration, 180)
        let fractional: [String: Any] = ["hash": "abc", "duration": 180.5]
        XCTAssertEqual(PublicDiscoveryTransport.normalizeKugou(fractional)?.duration, 180.5)
    }
    func testMD5MatchesPinnedProtocol() {
        XCTAssertEqual(ProtocolCrypto.md5("password"), "5f4dcc3b5aa765d61d8327deb882cf99")
    }
    func testEAPIReferenceVector() throws {
        XCTAssertEqual(try ProtocolCrypto.eapi(path: "/api/test", json: "{}"), "4DC723619A991588865191FD2F319BAD89A665F3FF2B75B10678911D4E9910E4690E5F68E0095E53773148F1312770C2786A0951D5B32887C8AE362CEF057841F3A83A42DA35956C149F335E924490D4")
    }
    func testQQAdvertisesOnlyVerifiedChannel() async {
        let service = OmniService()
        let methods = await service.loginMethods(provider: .qq)
        XCTAssertEqual(methods, [.qr])
    }
}
