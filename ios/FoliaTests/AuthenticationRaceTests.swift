import XCTest
@testable import Folia
// ios/FoliaTests/AuthenticationRaceTests.swift

final class AuthenticationRaceTests: XCTestCase {
    func testCancelledNeteaseAuthenticationCannotReplacePreviousAccount() async throws {
        let previous = MusicAccount(id: "old", provider: .netease, nickname: "Previous")
        let transport = NeteaseTransport(initialSession: ProviderSession(account: previous, cookies: ["MUSIC_U": "test-only-old-session"]))
        let expected = await transport.beginAuthentication()
        await transport.cancelAuthentication()
        do {
            try await transport.saveAccount(MusicAccount(id: "new", provider: .netease, nickname: "Late"), expected: expected)
            XCTFail("Cancelled authentication must not establish an account")
        } catch MusicError.sessionChanged { }
        let account = await transport.account()
        XCTAssertEqual(account?.id, "old")
    }
    func testReplacementNeteaseAttemptInvalidatesPreviousGeneration() async throws {
        let transport = NeteaseTransport(initialSession: ProviderSession())
        let old = await transport.beginAuthentication()
        _ = await transport.beginAuthentication()
        do { try await transport.checkAuthentication(old); XCTFail("Old login remained active") }
        catch MusicError.sessionChanged { }
    }
    func testCancelledKuGouQRIsRejectedBeforeAnyNetworkRequest() async throws {
        let account = MusicAccount(id: "old", provider: .kugou, nickname: "Previous")
        let transport = PublicDiscoveryTransport(initialSession: ProviderSession(account: account))
        let generation = await transport.beginKugouAuthentication()
        let pending = QRLogin(key: "test-only-no-upstream-key", url: URL(string: "https://example.com")!, authenticationGeneration: generation)
        await transport.cancelKugouAuthentication()
        do { _ = try await transport.pollKugouQR(pending); XCTFail("Cancelled QR must be rejected locally") }
        catch MusicError.sessionChanged { }
        let retained = await transport.kugouAccount()
        XCTAssertEqual(retained?.id, "old")
    }
}
