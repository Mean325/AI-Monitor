import Foundation
import XCTest

@testable import CodexLinxDisplay

final class GeminiUsageClientTests: XCTestCase {
  func testAggregatesTodayAndWeekTokens() throws {
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let brainRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemini-usage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: brainRoot) }

    let conv1 = brainRoot.appendingPathComponent("session-1/.system_generated/logs", isDirectory: true)
    let conv2 = brainRoot.appendingPathComponent("session-2/.system_generated/logs", isDirectory: true)
    try FileManager.default.createDirectory(at: conv1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: conv2, withIntermediateDirectories: true)

    // Entry from today: 100 input, 50 cache read, 40 output -> 190 tokens
    let todayTimestamp = formatter.string(from: now.addingTimeInterval(-300))
    let line1 = """
    {"type":"PLANNER_RESPONSE","created_at":"\(todayTimestamp)","model":"gemini-2.5-pro","input_tokens":100,"cache_read_tokens":50,"output_tokens":40}
    """

    // Entry from 3 days ago (this week): 200 input, 100 output -> 300 tokens
    let weekTimestamp = formatter.string(from: now.addingTimeInterval(-3 * 86400))
    let line2 = """
    {"type":"PLANNER_RESPONSE","created_at":"\(weekTimestamp)","model":"gemini-2.5-flash","input_tokens":200,"output_tokens":100}
    """

    // Entry from 15 days ago (older than week): 500 tokens
    let oldTimestamp = formatter.string(from: now.addingTimeInterval(-15 * 86400))
    let line3 = """
    {"type":"PLANNER_RESPONSE","created_at":"\(oldTimestamp)","model":"gemini-1.5-pro","input_tokens":500,"output_tokens":0}
    """

    try (line1 + "\n" + line2 + "\n").write(to: conv1.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
    try (line3 + "\n").write(to: conv2.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

    let snapshot = try GeminiUsageClient.aggregate(brainURL: brainRoot, now: now)

    XCTAssertEqual(snapshot.todayTokens, 190)
    XCTAssertEqual(snapshot.weekTokens, 490) // 190 + 300
    XCTAssertEqual(snapshot.todaySessions, 1)
    XCTAssertEqual(snapshot.model, "gemini-2.5-pro")
    XCTAssertNotNil(snapshot.lastActiveDate)
  }

  func testMissingBrainDirectoryReturnsZeroSnapshot() throws {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemini-missing-\(UUID().uuidString)", isDirectory: true)

    let snapshot = try GeminiUsageClient.aggregate(brainURL: missing, now: Date())
    XCTAssertEqual(snapshot.todayTokens, 0)
    XCTAssertEqual(snapshot.weekTokens, 0)
    XCTAssertEqual(snapshot.todaySessions, 0)
    XCTAssertNil(snapshot.model)
    XCTAssertNil(snapshot.lastActiveDate)
  }
}
