import XCTest
// ios/FoliaUITests/LyricsRenderingTests.swift

final class LyricsRenderingTests: XCTestCase {
    func testBundledLyricsRenderInPortraitAndLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--lyrics-validation"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let ready = app.staticTexts["lyrics.validation.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 45), "The bundled WKWebView must render real lyrics, not only show the native shell")
        XCTAssertFalse(app.staticTexts["lyrics.validation.error"].exists)
        XCTAssertTrue(app.staticTexts["lyrics.validation.portrait"].exists)
        attachScreenshot(app, name: "lyrics-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["lyrics.validation.landscape"].waitForExistence(timeout: 15))
        XCTAssertTrue(ready.exists)
        XCTAssertFalse(app.staticTexts["lyrics.validation.error"].exists)
        attachScreenshot(app, name: "lyrics-landscape")
    }
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
