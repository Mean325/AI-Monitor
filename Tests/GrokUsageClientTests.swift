import XCTest

@testable import CodexLinxDisplay

final class GrokUsageClientTests: XCTestCase {
  func testRemainingPercentIsComplementOfUsedPercent() throws {
    let snapshot = try GrokUsageClient.makeSnapshot(
      billingData: billingJSON(usedPercent: 8),
      userData: userJSON(tier: "GrokPro")
    )

    XCTAssertEqual(snapshot.remainingPercent, 92)
    XCTAssertEqual(snapshot.usedPercent, 8)
    XCTAssertEqual(snapshot.windowTitle, "本周剩余")
    XCTAssertEqual(snapshot.planDisplayName, "Grok Pro")
    XCTAssertEqual(snapshot.periodType, .weekly)
    XCTAssertNotNil(snapshot.periodEnd)
    XCTAssertNotEqual(snapshot.remainingPercent, Int(snapshot.usedPercent))
  }

  func testPrefersGrokBuildProductUsagePercent() throws {
    let json = """
      {
        "config": {
          "currentPeriod": {
            "type": "USAGE_PERIOD_TYPE_WEEKLY",
            "start": "2026-08-31T05:42:56.561001+00:00",
            "end": "2026-09-07T05:42:56.561001+00:00"
          },
          "creditUsagePercent": 40.0,
          "productUsage": [
            {"product": "Other", "usagePercent": 90.0},
            {"product": "GrokBuild", "usagePercent": 12.0}
          ],
          "prepaidBalance": {"val": 0},
          "onDemandCap": {"val": 0},
          "onDemandUsed": {"val": 0}
        }
      }
      """.data(using: .utf8)!

    let snapshot = try GrokUsageClient.makeSnapshot(billingData: json)
    XCTAssertEqual(snapshot.usedPercent, 12)
    XCTAssertEqual(snapshot.remainingPercent, 88)
  }

  func testZeroUsageIsFullRemaining() throws {
    let snapshot = try GrokUsageClient.makeSnapshot(billingData: billingJSON(usedPercent: 0))
    XCTAssertEqual(snapshot.remainingPercent, 100)
    XCTAssertEqual(snapshot.remainingProgress, 1, accuracy: 0.0001)
  }

  func testMissingUsageFieldsInValidPeriodMeansZeroUsage() throws {
    let json = """
      {
        "config": {
          "currentPeriod": {
            "type": "USAGE_PERIOD_TYPE_WEEKLY",
            "start": "2026-08-31T05:42:56.561001+00:00",
            "end": "2026-09-07T05:42:56.561001+00:00"
          },
          "productUsage": [],
          "prepaidBalance": {"val": 0},
          "onDemandCap": {"val": 0},
          "onDemandUsed": {"val": 0}
        }
      }
      """.data(using: .utf8)!

    let snapshot = try GrokUsageClient.makeSnapshot(billingData: json)
    XCTAssertEqual(snapshot.usedPercent, 0)
    XCTAssertEqual(snapshot.remainingPercent, 100)
    XCTAssertEqual(snapshot.periodType, .weekly)
  }

  func testExhaustedUsageIsZeroRemaining() throws {
    let snapshot = try GrokUsageClient.makeSnapshot(billingData: billingJSON(usedPercent: 100))
    XCTAssertEqual(snapshot.remainingPercent, 0)
    XCTAssertEqual(snapshot.remainingProgress, 0, accuracy: 0.0001)
  }

  func testRoundsRemainingPercentFromFractionalUsed() throws {
    let snapshot = try GrokUsageClient.makeSnapshot(billingData: billingJSON(usedPercent: 8.4))
    XCTAssertEqual(snapshot.remainingPercent, 92)
  }

  func testMonthlyPeriodTitle() throws {
    let json = """
      {
        "config": {
          "currentPeriod": {
            "type": "USAGE_PERIOD_TYPE_MONTHLY",
            "start": "2026-08-01T00:00:00+00:00",
            "end": "2026-09-01T00:00:00+00:00"
          },
          "creditUsagePercent": 25.0
        }
      }
      """.data(using: .utf8)!
    let snapshot = try GrokUsageClient.makeSnapshot(billingData: json)
    XCTAssertEqual(snapshot.periodType, .monthly)
    XCTAssertEqual(snapshot.windowTitle, "本月剩余")
    XCTAssertEqual(snapshot.remainingPercent, 75)
  }

  func testMissingUsagePercentThrows() {
    let json = #"{"config":{"prepaidBalance":{"val":0}}}"#.data(using: .utf8)!
    XCTAssertThrowsError(try GrokUsageClient.makeSnapshot(billingData: json)) { error in
      XCTAssertEqual(error as? GrokClientError, .invalidResponse)
    }
  }

  func testParseAuthPicksNewestProfile() throws {
    let json = """
      {
        "https://auth.x.ai::old": {
          "key": "old-token",
          "expires_at": "2026-08-01T00:00:00.000000Z",
          "oidc_client_id": "old"
        },
        "https://auth.x.ai::new": {
          "key": "new-token",
          "refresh_token": "refresh",
          "expires_at": "2026-08-31T12:00:00.000000Z",
          "oidc_client_id": "new"
        }
      }
      """.data(using: .utf8)!

    let credential = try GrokUsageClient.parseCredential(from: json)
    XCTAssertEqual(credential.accessToken, "new-token")
    XCTAssertEqual(credential.clientId, "new")
    XCTAssertEqual(credential.refreshToken, "refresh")
  }

  func testParseAuthRejectsEmptyFile() {
    XCTAssertThrowsError(try GrokUsageClient.parseCredential(from: Data("{}".utf8))) { error in
      XCTAssertEqual(error as? GrokClientError, .authInvalid)
    }
  }

  func testSampleCardExposesRemainingNotUsed() {
    XCTAssertEqual(GrokUsageSnapshot.sample.remainingPercent, 92)
    XCTAssertEqual(GrokUsageSnapshot.sample.usedPercent, 8)
    XCTAssertTrue(GrokUsageSnapshot.sample.windowTitle.contains("剩余"))
    XCTAssertFalse(GrokUsageSnapshot.sample.windowTitle.contains("已用"))
  }

  private func billingJSON(usedPercent: Double) -> Data {
    """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-08-31T05:42:56.561001+00:00",
          "end": "2026-09-07T05:42:56.561001+00:00"
        },
        "creditUsagePercent": \(usedPercent),
        "productUsage": [{"product": "GrokBuild", "usagePercent": \(usedPercent)}],
        "prepaidBalance": {"val": 0},
        "onDemandCap": {"val": 0},
        "onDemandUsed": {"val": 0},
        "billingPeriodStart": "2026-08-31T05:42:56.561001+00:00",
        "billingPeriodEnd": "2026-09-07T05:42:56.561001+00:00"
      }
    }
    """.data(using: .utf8)!
  }

  private func userJSON(tier: String) -> Data {
    """
    {"subscriptionTier":"\(tier)","hasGrokCodeAccess":true}
    """.data(using: .utf8)!
  }
}
