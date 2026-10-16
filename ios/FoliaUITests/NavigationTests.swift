import XCTest

// FoliaUITests/NavigationTests.swift — native shell accessibility and rotation checks.
final class NavigationTests: XCTestCase {
    func testNativeTabsAndRotationPreserveNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 10))
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "search-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "search-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        let landscape = XCTAttachment(screenshot: app.screenshot()); landscape.name = "search-landscape"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["账户与音乐服务"].exists)
    }
}


