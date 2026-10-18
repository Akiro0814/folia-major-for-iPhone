import XCTest
@testable import Folia
// ios/FoliaTests/BodianTests.swift

final class BodianTests: XCTestCase {
    func testSignatureMatchesPinnedPackageAndFormEncoding() {
        let fields = [("keyword", "你好 +"), ("uid", "-1"), ("token", ""), ("timestamp", "123")]
        XCTAssertEqual(BodianProvider.signature(path: "/api/test", fields: fields, body: "{\"x\":1}"), "d210ad052575fb6dd07729c0373fba1d")
        XCTAssertEqual(BodianProvider.signature(path: "/api/test", fields: fields), "9402cdefa8e9c672433ca1803a9b99b2")
        XCTAssertEqual(BodianProvider.queryString([("q", "你好 +~")]), "q=%E4%BD%A0%E5%A5%BD+%2B%7E")
    }
    func testObfuscatedWordTimingUsesPerFileOctalFactors() {
        let lyrics = BodianProvider.decodeLyrics("[00:01.00]<2200,1800>Hi[kuwo:13]")
        XCTAssertEqual(lyrics.original, "[00:01.00]Hi")
        XCTAssertEqual(lyrics.wordTimed, "[00:01.00]<2000,200>Hi")
    }
    func testAccountExchangeRejectsContradictoryIdentities() {
        XCTAssertThrowsError(try BodianProvider.loginAccount(["id": "1", "token": "t", "userInfo": ["uid": "2"]]))
        XCTAssertNoThrow(try BodianProvider.loginAccount(["id": "1", "token": "t", "userInfo": ["uid": "1", "nickname": "Test"]]))
        XCTAssertNoThrow(try BodianProvider.loginAccount(["id": "12345678901234567890", "token": "t", "userInfo": ["uid": "12345678901234567890"]]))
        XCTAssertThrowsError(try BodianProvider.loginAccount(["id": NSNumber(value: 9_007_199_254_740_992 as Int64), "token": "t"]))
        XCTAssertThrowsError(try BodianProvider.loginAccount(["id": true, "token": "t"]))
    }
    func testPreviewNeverBecomesFullTrack() {
        XCTAssertThrowsError(try BodianProvider.validateRights(["status": 3, "audition": ["url": "https://example.test/clip.mp3"]]))
        XCTAssertThrowsError(try BodianProvider.validateRights(["status": 7]))
    }
    func testChunkedHTTPResponseDecoding() throws {
        let response = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n".utf8)
        XCTAssertEqual(String(decoding: try BodianGETBodyHTTP.decode(response), as: UTF8.self), "Wikipedia")
        XCTAssertThrowsError(try BodianGETBodyHTTP.decode(Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".utf8)))
    }
}
