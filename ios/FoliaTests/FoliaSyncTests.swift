import XCTest
@testable import Folia
// ios/FoliaTests/FoliaSyncTests.swift

final class FoliaSyncTests: XCTestCase {
    func testUploadPreservesDesktopOnlyVisualSettings() throws {
        let remote: [String: Any] = ["schemaVersion": 1, "updatedAt": "2026-10-16T00:00:00.000Z", "data": ["classicTuning": ["blur": 7], "lyricsFontWeight": 600]]
        var visual = VisualSettings(); visual.renderer = "sonnet"; visual.fontSize = 54
        let merged = try FoliaSyncService.merge(visual, into: remote)
        let data = try XCTUnwrap(merged["data"] as? [String: Any])
        XCTAssertEqual(data["visualizerMode"] as? String, "sonnet")
        XCTAssertEqual(data["lyricsFontScale"] as? Double, 1.5)
        XCTAssertEqual(data["lyricsFontWeight"] as? Int, 600)
        XCTAssertEqual((data["classicTuning"] as? [String: Int])?["blur"], 7)
    }
    func testPullMapsDesktopSubtitleAndScale() throws {
        let record: [String: Any] = ["schemaVersion": 1, "updatedAt": "2026-10-16T00:00:00.000Z", "data": ["visualizerMode": "classic", "lyricsFontScale": 2.0, "subtitleContentMode": "both", "showSubtitleTranslation": true]]
        let visual = try FoliaSyncService.visualSettings(record, existing: VisualSettings())
        XCTAssertEqual(visual.fontSize, 72)
        XCTAssertTrue(visual.showRomanization)
        XCTAssertTrue(visual.showTranslation)
    }
    func testRejectsUnknownSchemaRatherThanOverwritingServerRecord() {
        XCTAssertThrowsError(try FoliaSyncService.merge(VisualSettings(), into: ["schemaVersion": 2, "data": [:]]))
    }
}
