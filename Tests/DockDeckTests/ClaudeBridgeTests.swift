import Foundation
import XCTest

@testable import DockDeckClaudeBridge

final class ClaudeBridgeTests: XCTestCase {
    func testCacheDropsAllSessionFieldsExceptRateLimitsAndObservationTime() throws {
        let input = Data(
            #"""
            {
              "session_id": "must-not-be-cached",
              "transcript_path": "/private/conversation.jsonl",
              "rate_limits": {
                "five_hour": {
                  "used_percentage": 35,
                  "resets_at": 3000
                }
              }
            }
            """#.utf8)

        let cache = try XCTUnwrap(
            ClaudeBridgePayload.cacheData(from: input, observedAt: 2000))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: cache) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["observed_at", "rate_limits"])
        XCTAssertNil(object["session_id"])
        XCTAssertNil(object["transcript_path"])
    }

    func testStatusLineUsesAvailableQuotaWindows() {
        let input = Data(
            #"""
            {
              "rate_limits": {
                "five_hour": { "used_percentage": 35.4 },
                "seven_day": { "used_percentage": 48.1 }
              }
            }
            """#.utf8)

        XCTAssertEqual(
            ClaudeBridgePayload.statusLine(from: input),
            "Claude 5h 35% · 7d 48%")
    }
}
