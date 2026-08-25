import XCTest
@testable import AIRecorder

final class LibraryRowMetadataTests: XCTestCase {
    func testShortDateUsesLocalizedOrderingAndLeadingZeroes() {
        let date = Date(timeIntervalSince1970: 1_787_560_320)

        XCTAssertEqual(
            shortLibraryDate(date, locale: Locale(identifier: "es_ES")),
            "24/08/26"
        )
        XCTAssertEqual(
            shortLibraryDate(date, locale: Locale(identifier: "en_US")),
            "08/24/26"
        )
    }
}
