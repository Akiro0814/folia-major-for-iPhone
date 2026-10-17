import XCTest
@testable import Folia

// FoliaTests/NativePersistenceTests.swift — invalid imported visuals and local-library identities cannot enter iOS state.
final class NativePersistenceTests: XCTestCase {
    func testLocalAudioProviderIsRejectedByPersistedTrackDecoder() {
        let json = #"{"mediaID":"file:///music/song.mp3","provider":"local","title":"Local audio","artist":"Local","album":"","duration":30}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Track.self, from: Data(json.utf8)))
    }
    func testVisualValidationRejectsUnboundedValuesAndInvalidPalette() {
        var settings = VisualSettings()
        settings.fontSize = .infinity
        XCTAssertThrowsError(try settings.validated())
        settings.fontSize = 36; settings.lyricOffset = 6000
        XCTAssertThrowsError(try settings.validated())
        settings.lyricOffset = 0; settings.themeColors = ["red"]
        XCTAssertThrowsError(try settings.validated())
    }
    func testOldVisualExportWithoutPaletteStillLoads() throws {
        let json = #"{"renderer":"classic","background":"common","showTranslation":true,"showRomanization":false,"lyricOffset":0,"fontSize":36}"#
        let settings = try JSONDecoder().decode(VisualSettings.self, from: Data(json.utf8)).validated()
        XCTAssertNil(settings.themeColors)
    }
}
