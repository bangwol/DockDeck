import XCTest

@testable import DockDeck

final class FoldedDeckSummaryTests: XCTestCase {
    func testUsagePercentRequiresLiveFiniteValue() {
        XCTAssertEqual(FoldedDeckSummary.usagePercent(45.6, freshness: .live), "46%")
        XCTAssertEqual(FoldedDeckSummary.usagePercent(45.6, freshness: .stale), "--")
        XCTAssertEqual(FoldedDeckSummary.usagePercent(.nan, freshness: .live), "--")
    }
}
