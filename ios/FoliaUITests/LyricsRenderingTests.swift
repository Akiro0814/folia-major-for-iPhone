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
        XCTAssertTrue(ready.waitForExistence(timeout: 45), "The bundled WKWebView must render real lyrics: \(app.staticTexts["lyrics.validation.diagnostics"].firstMatch.exists ? app.staticTexts["lyrics.validation.diagnostics"].firstMatch.label : "no diagnostics")")
        XCTAssertFalse(app.staticTexts["lyrics.validation.error"].exists)
        XCTAssertTrue(app.staticTexts["lyrics.validation.portrait"].exists)
        attachScreenshot(app, name: "lyrics-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["lyrics.validation.landscape"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        // Geometry changes before the system rotation and WebKit compositing finish.
        Thread.sleep(forTimeInterval: 1.5)
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
