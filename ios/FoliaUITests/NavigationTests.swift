import XCTest

// FoliaUITests/NavigationTests.swift — native navigation survives rotation and exits the system search interaction.
final class NavigationTests: XCTestCase {
    func testNativeTabsAndRotationPreserveNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 10))
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "search-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        let landscape = XCTAttachment(screenshot: app.screenshot()); landscape.name = "search-landscape"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate { _, _ in app.frame.height > app.frame.width }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        // iOS 26 search tabs may retain the expanded search interaction after rotation.
        let cancelSearch = app.buttons["取消"].firstMatch
        if cancelSearch.waitForExistence(timeout: 2) { cancelSearch.tap() }
        let settings = app.buttons["设置"].firstMatch
        if !settings.waitForExistence(timeout: 2) {
            let collapsedTabs = app.buttons["曲库"].firstMatch
            XCTAssertTrue(collapsedTabs.waitForExistence(timeout: 5))
            collapsedTabs.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["账户与音乐服务"].waitForExistence(timeout: 5))
    }
}

