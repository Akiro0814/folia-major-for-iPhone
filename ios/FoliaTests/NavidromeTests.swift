import XCTest
@testable import Folia
// ios/FoliaTests/NavidromeTests.swift

final class NavidromeTests: XCTestCase {
    func testSaltedAuthenticationPreservesServerPathAndDoesNotSendPassword() throws {
        let config = NavidromeConfiguration(serverURL: "https://music.example.test/navidrome/", username: "用户 +", password: "password")
        let url = try NavidromeProvider.url(configuration: config, endpoint: "search3", parameters: [.init(name: "query", value: "a & b")], salt: "salt")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(parts.path, "/navidrome/rest/search3")
        XCTAssertEqual(values["u"], "用户 +")
        XCTAssertTrue(url.absoluteString.contains("%2B"), "Literal plus signs must survive form-style server query decoding")
        XCTAssertEqual(values["query"], "a & b")
        XCTAssertEqual(values["t"], ProtocolCrypto.md5("passwordsalt"))
        XCTAssertEqual(values["s"], "salt")
        XCTAssertNil(values["p"])
        XCTAssertFalse(url.absoluteString.contains("password"))
    }
    func testRejectsEmbeddedCredentialsAndNonNetworkURLs() {
        for input in ["file:///tmp/music", "https://user:pass@example.test", "https://example.test/?token=x"] {
            XCTAssertThrowsError(try NavidromeProvider.url(configuration: .init(serverURL: input, username: "u", password: "p"), endpoint: "ping", salt: "salt"))
        }
    }
    func testServerFailureIsNotReturnedAsEmptySuccess() throws {
        let data = Data(#"{"subsonic-response":{"status":"failed","error":{"code":40,"message":"Wrong username or password"}}}"#.utf8)
        XCTAssertThrowsError(try NavidromeProvider.decode(data)) { error in
            guard case MusicError.server(let code, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(code, 40)
        }
    }
    func testStructuredLyricsUseMillisecondsAndPreserveUnsyncedText() {
        let timed: [String: Any] = ["synced": true, "offset": 100, "line": [["start": 1500, "value": "hello"], ["start": 2300, "value": "world"]]]
        XCTAssertEqual(NavidromeProvider.lyricText(timed), "[00:01.60]hello\n[00:02.40]world")
        XCTAssertEqual(NavidromeProvider.lyricText(["synced": false, "line": [["value": "hello"]]]), "hello")
    }
}
