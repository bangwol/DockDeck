import Foundation
import XCTest

@testable import DockDeckClaudeBridge

final class ClaudeBridgeTests: XCTestCase {
    func testInputReaderBoundsReadsBeforeRejectingOversizedInput() throws {
        let limit = ClaudeBridgeRuntime.maximumInputBytes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for size in [0, limit, limit + 1, limit * 2] {
            try Data(repeating: 32, count: size).write(to: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            if size <= limit {
                XCTAssertEqual(try ClaudeBridgeRuntime.readInput(from: handle).count, size)
            } else {
                XCTAssertThrowsError(try ClaudeBridgeRuntime.readInput(from: handle)) { error in
                    guard case ClaudeBridgeRuntime.UsageError.inputTooLarge = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                }
                XCTAssertEqual(try handle.offset(), UInt64(limit + 1))
            }
        }
    }

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

    func testObservationTimeUsesTranscriptModificationWithoutPersistingPath() {
        let input = Data(
            #"{"transcript_path":"/private/conversation.jsonl","rate_limits":{}}"#.utf8)

        let observedAt = ClaudeBridgePayload.observationTime(
            from: input,
            fallback: 2_000,
            fileModificationDate: { path in
                XCTAssertEqual(path, "/private/conversation.jsonl")
                return Date(timeIntervalSince1970: 1_900)
            })

        XCTAssertEqual(observedAt, 1_900)
    }

    func testObservationTimeFallsBackAndRejectsFutureModificationDate() {
        let missingPath = ClaudeBridgePayload.observationTime(
            from: Data(#"{"rate_limits":{}}"#.utf8),
            fallback: 2_000,
            fileModificationDate: { _ in XCTFail("Unexpected file lookup"); return nil })
        let futurePath = ClaudeBridgePayload.observationTime(
            from: Data(#"{"transcript_path":"/future"}"#.utf8),
            fallback: 2_000,
            fileModificationDate: { _ in Date(timeIntervalSince1970: 3_000) })

        XCTAssertEqual(missingPath, 2_000)
        XCTAssertEqual(futurePath, 2_000)
    }

    func testStatusLineUsesAvailableQuotaWindows() {
        let input = Data(
            #"""
            {
              "rate_limits": {
                "five_hour": { "used_percentage": 35.4 },
                "seven_day": { "used_percentage": 48.1 },
                "fable": { "used_percentage": 62.8 }
              }
            }
            """#.utf8)

        XCTAssertEqual(
            ClaudeBridgePayload.statusLine(from: input),
            "Claude 5h 65% left · 7d 52% left · FBL 37% left")
    }

    func testStatusLineClampsRemainingQuota() {
        let input = Data(
            #"{"rate_limits":{"five_hour":{"used_percentage":110},"seven_day":{"used_percentage":-5}}}"#.utf8)

        XCTAssertEqual(
            ClaudeBridgePayload.statusLine(from: input),
            "Claude 5h 0% left · 7d 100% left")
    }
}
