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
    func testMD5MatchesPinnedProtocol() {
        XCTAssertEqual(ProtocolCrypto.md5("password"), "5f4dcc3b5aa765d61d8327deb882cf99")
    }
    func testEAPIReferenceVector() throws {
        XCTAssertEqual(try ProtocolCrypto.eapi(path: "/api/test", json: "{}"), "4DC723619A991588865191FD2F319BAD89A665F3FF2B75B10678911D4E9910E4690E5F68E0095E53773148F1312770C2786A0951D5B32887C8AE362CEF057841F3A83A42DA35956C149F335E924490D4")
    }
    func testUnsupportedProvidersHaveNoAdvertisedLogin() async {
        let service = OmniService()
        let methods = await service.loginMethods(provider: .qq)
        XCTAssertTrue(methods.isEmpty)
    }
}

