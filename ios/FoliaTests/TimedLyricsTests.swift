import XCTest
@testable import Folia
// ios/FoliaTests/TimedLyricsTests.swift

final class TimedLyricsTests: XCTestCase {
    func testKRCMatchesPinnedXORZlibVector() throws {
        let encoded = "a3JjMTjb6kGOA0B3Yb6EHB7jW1mQdtGEFv+9juY3gAyyV5yV4tt1d+dufkI="
        XCTAssertEqual(try TimedLyricsDecoder.krc(encoded), "[0,1000]<0,500,0>Hello<500,500,0> world")
    }
    func testQRCMatchesExistingFoliaCustomDESVector() throws {
        let encoded = "bb1db48dc814ca5230599ef7ce939c997ae566073f496542db7b9df043c1569afa9866d695df72d3"
        XCTAssertEqual(try TimedLyricsDecoder.qrc(encoded), "[0,1000]Hello(0,500) world(500,500)")
    }
    func testMalformedCompressedPayloadFails() {
        XCTAssertThrowsError(try TimedLyricsDecoder.krc("AAAA"))
        XCTAssertThrowsError(try TimedLyricsDecoder.qrc("g0"))
        XCTAssertThrowsError(try TimedLyricsDecoder.inflate(Data([1, 2, 3])))
    }
    func testOldTrackDecodesWithoutNewMetadata() throws {
        let data = Data(#"{"mediaID":"1","provider":"netease","title":"A","artist":"B"}"#.utf8)
        let track = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(track.providerData, [:])
        XCTAssertEqual(track.album, "")
    }
    func testNavidromeIdentityIncludesServer() {
        let a = Track(mediaID: "1", provider: .navidrome, title: "A", artist: "B", providerData: ["serverNamespace": "one"])
        let b = Track(mediaID: "1", provider: .navidrome, title: "A", artist: "B", providerData: ["serverNamespace": "two"])
        XCTAssertNotEqual(a.id, b.id)
    }
    func testMQTTConnectAndSubscribeVectors() {
        let connect = QQMQTT.connect("qr")
        XCTAssertEqual(connect.first, 0x10)
        XCTAssertTrue(connect.range(of: Data("management.user".utf8)) != nil)
        let subscribe = QQMQTT.subscribe("qr")
        XCTAssertEqual(subscribe.first, 0x82)
        XCTAssertTrue(subscribe.range(of: Data("management.qrcode_login/qr".utf8)) != nil)
    }
}
