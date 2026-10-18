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
    func testTuningUploadMigratesLegacyModesWithoutErasingUneditedFields() throws {
        let remote: [String: Any] = ["schemaVersion": 1, "updatedAt": "2026-10-16T00:00:00.000Z", "data": ["classicTuning": ["blur": 7, "desktopOnly": true], "sonnetTuning": ["spacing": 3]]]
        var visual = VisualSettings(); visual.visualizerTunings = ["classic": ["blur": .number(2)]]
        let merged = try FoliaSyncService.merge(visual, into: remote)
        let tuning = try XCTUnwrap((merged["data"] as? [String: Any])?["visualizerTunings"] as? [String: [String: Any]])
        XCTAssertEqual(tuning["classic"]?["blur"] as? Double, 2)
        XCTAssertEqual(tuning["classic"]?["desktopOnly"] as? Bool, true)
        XCTAssertEqual(tuning["sonnet"]?["spacing"] as? Int, 3)
        let downloaded = try FoliaSyncService.visualSettings(merged, existing: VisualSettings())
        XCTAssertEqual(downloaded.visualizerTunings?["classic"]?["blur"], .number(2))
    }
    func testBackgroundTuningsUseOriginalTopLevelKeys() throws {
        let remote: [String: Any] = ["schemaVersion": 1, "updatedAt": "2026-10-16T00:00:00.000Z", "data": ["monetBackgroundTuning": ["speed": 1, "desktopOnly": true]]]
        var visual = VisualSettings(); visual.visualizerTunings = ["monet_background": ["speed": .number(2)]]
        let merged = try FoliaSyncService.merge(visual, into: remote)
        let data = try XCTUnwrap(merged["data"] as? [String: Any])
        let background = try XCTUnwrap(data["monetBackgroundTuning"] as? [String: Any])
        XCTAssertEqual(background["speed"] as? Double, 2)
        XCTAssertEqual(background["desktopOnly"] as? Bool, true)
        XCTAssertNil((data["visualizerTunings"] as? [String: Any])?["monet_background"])
        let downloaded = try FoliaSyncService.visualSettings(merged, existing: VisualSettings())
        XCTAssertEqual(downloaded.visualizerTunings?["monet_background"]?["speed"], .number(2))
    }
}
