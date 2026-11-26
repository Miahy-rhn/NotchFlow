import XCTest
@testable import NookFlow

final class NotchGeometryTests: XCTestCase {
    private let withNotch = NotchGeometry(hasNotch: true, notchWidth: 200, notchHeight: 38)

    func testCompactSizeIsSlightlyWiderThanTheNotch() {
        XCTAssertEqual(withNotch.compactSize, CGSize(width: 224, height: 38))
    }

    func testBadgeWidensThePanelOnBothSidesOfTheNotch() {
        XCTAssertEqual(withNotch.compactSize(withBadge: true), CGSize(width: 332, height: 38))
        XCTAssertEqual(withNotch.compactSize(withBadge: false), withNotch.compactSize)
    }

    func testFallbackWithoutNotchIsACenteredPill() {
        let fallback = NotchGeometry.fallback
        XCTAssertFalse(fallback.hasNotch)
        XCTAssertEqual(fallback.compactSize, CGSize(width: 180, height: 32))
        XCTAssertEqual(fallback.compactSize(withBadge: true).width, 180)
    }

    func testExpandedPanelStartsBelowTheNotch() {
        XCTAssertEqual(withNotch.expandedSize.height, 38 + 210)
        XCTAssertGreaterThan(withNotch.expandedSize.width, withNotch.compactSize(withBadge: true).width)
    }
}
