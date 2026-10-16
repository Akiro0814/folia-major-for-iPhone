import XCTest
@testable import Folia

// FoliaTests/PlaybackQueueTests.swift — repeat and identity-sensitive queue regression tests.
final class PlaybackQueueTests: XCTestCase {
    func testEndOfQueueStopsUnlessRepeatAll() {
        var queue = PlaybackQueue(ids: ["netease:1", "qq:1"], index: 1)
        XCTAssertNil(queue.advance(automatic: true))
        queue.repeatMode = .all
        XCTAssertEqual(queue.advance(automatic: true), 0)
    }
    func testRepeatOneOnlyAffectsAutomaticAdvance() {
        var queue = PlaybackQueue(ids: ["a", "b"], index: 0)
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(automatic: true), 0)
        XCTAssertEqual(queue.advance(automatic: false), 1)
    }
    func testRemoveCurrentPreservesValidIndex() {
        var queue = PlaybackQueue(ids: ["a", "b"], index: 1)
        queue.remove(at: 1)
        XCTAssertEqual(queue.index, 0)
        queue.remove(at: 0)
        XCTAssertNil(queue.index)
    }
}
