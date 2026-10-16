import XCTest
@testable import Folia

// FoliaTests/AIThemeTests.swift — generated colors must stay bounded, semantic and portable.
final class AIThemeTests: XCTestCase {
    func testPaletteRequiresFourHexColors() throws {
        XCTAssertEqual(try AIThemeService.validate(["#101010", "#FAFAFA", "#556633", "#999999"]).count, 4)
        XCTAssertThrowsError(try AIThemeService.validate(["red", "#FAFAFA", "#556633", "#999999"]))
        XCTAssertThrowsError(try AIThemeService.validate(["#FFFFFF"]))
    }
    func testEndpointRequiresSecureTransportWithoutCredentials() {
        XCTAssertThrowsError(try AIThemeService.endpoint("http://example.com/v1"))
        XCTAssertThrowsError(try AIThemeService.endpoint("https://user:password@example.com/v1"))
        XCTAssertEqual(try AIThemeService.endpoint("https://example.com/v1").path, "/v1/chat/completions")
    }
}
