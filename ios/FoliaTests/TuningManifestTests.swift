import XCTest
@testable import Folia

// FoliaTests/TuningManifestTests.swift — editable renderer values preserve primitive types and stay bounded.
final class TuningManifestTests: XCTestCase {
    func testPrimitiveAndNestedDefaultTypesRoundTrip() throws {
        let data = Data(#"{"enabled":true,"amount":1.25,"mode":"smooth","geometry":{"ring":false}}"#.utf8)
        let object = try JSONDecoder().decode([String: TuningValue].self, from: data)
        XCTAssertEqual(object["enabled"], .bool(true))
        XCTAssertEqual(object["amount"], .number(1.25))
        XCTAssertEqual(object["geometry"], .object(["ring": .bool(false)]))
        XCTAssertEqual(try JSONDecoder().decode([String: TuningValue].self, from: JSONEncoder().encode(object)), object)
    }
    func testUnboundedTuningValuesAreRejected() {
        XCTAssertThrowsError(try TuningManifest.validate(["classic": ["amount": .number(1_000_000)]]))
        XCTAssertThrowsError(try TuningManifest.validate(["classic": ["amount": .number(.nan)]]))
        XCTAssertThrowsError(try TuningManifest.validate(["classic": ["label": .string(String(repeating: "x", count: 1025))]]))
        let tooMany = Dictionary(uniqueKeysWithValues: (0...256).map { ("field\($0)", TuningValue.bool(true)) })
        XCTAssertThrowsError(try TuningManifest.validate(["classic": tooMany]))
    }
}
