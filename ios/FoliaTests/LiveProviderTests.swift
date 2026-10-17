import XCTest
@testable import Folia
// ios/FoliaTests/LiveProviderTests.swift

final class LiveProviderTests: XCTestCase {
    // Explicit opt-in only. These probes never log in, send SMS, or mutate user data.
    func testNativeDirectNeteaseSearch() async throws {
        try requireLiveProbe()
        let tracks = try await OmniService().search("周杰伦", provider: .netease)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(tracks.allSatisfy { $0.provider == .netease && !$0.mediaID.isEmpty })
    }
    func testNativeDirectKuGouSearch() async throws {
        try requireLiveProbe()
        let tracks = try await OmniService().search("周杰伦", provider: .kugou)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(tracks.allSatisfy { $0.provider == .kugou && !$0.mediaID.isEmpty })
    }
    private func requireLiveProbe() throws {
        guard ProcessInfo.processInfo.environment["FOLIA_LIVE_PROBES"] == "1" || ProcessInfo.processInfo.arguments.contains("FOLIA_LIVE_PROBES") else {
            throw XCTSkip("Set FOLIA_LIVE_PROBES=1 for anonymous upstream read-only probes.")
        }
    }
}
