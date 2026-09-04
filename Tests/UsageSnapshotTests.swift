import XCTest

@testable import CodexLinxDisplay

final class UsageSnapshotTests: XCTestCase {
  func testParsesFiveHourWindowWithoutChangingWeeklyWindow() throws {
    for reversed in [false, true] {
      let short = #"{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000}"#
      let week = #"{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800500000}"#
      let json = """
        {"rateLimitsByLimitId":{"codex":{
          "primary":\(reversed ? week : short),
          "secondary":\(reversed ? short : week)
        }}}
        """
      let snapshot = try CodexRateLimitClient.makeSnapshot(from: Data(json.utf8))
      XCTAssertEqual(snapshot.remainingPercent, 90)
      XCTAssertEqual(snapshot.windowMinutes, 10080)
      XCTAssertEqual(snapshot.resetDate, Date(timeIntervalSince1970: 1800500000))
      XCTAssertEqual(snapshot.fiveHourRemainingPercent, 75)
      XCTAssertEqual(snapshot.fiveHourResetDate, Date(timeIntervalSince1970: 1800000000))
    }
  }

  func testMissingFiveHourWindowDoesNotBorrowWeeklyValues() throws {
    let data = Data(#"{"rateLimits":{"secondary":{"usedPercent":10,"windowDurationMins":10080}}}"#.utf8)
    let snapshot = try CodexRateLimitClient.makeSnapshot(from: data)
    XCTAssertNil(snapshot.fiveHourRemainingPercent)
    XCTAssertNil(snapshot.fiveHourResetDate)
  }

  func testZeroFiveHourUsageAndMissingResetDate() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300}}}"#.utf8)
    let snapshot = try CodexRateLimitClient.makeSnapshot(from: data)
    XCTAssertEqual(snapshot.fiveHourRemainingPercent, 100)
    XCTAssertNil(snapshot.fiveHourResetDate)
  }

  func testWeeklyLabelsAreChinese() {
    let snapshot = UsageSnapshot(
      remainingPercent: 98,
      resetDate: nil,
      windowMinutes: 10_080,
      availableResetCount: 3,
      planType: "plus"
    )

    XCTAssertEqual(snapshot.windowTitle, "本周剩余")
    XCTAssertEqual(snapshot.windowDescription, "7 天周期")
  }

  func testFiveHourLabelsAreChinese() {
    let snapshot = UsageSnapshot(
      remainingPercent: 50,
      resetDate: nil,
      windowMinutes: 300,
      availableResetCount: 0,
      planType: nil
    )

    XCTAssertEqual(snapshot.windowTitle, "5 小时剩余")
    XCTAssertEqual(snapshot.windowDescription, "5 小时周期")
  }
}
