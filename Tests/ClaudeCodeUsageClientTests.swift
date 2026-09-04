import Foundation
import XCTest

@testable import CodexLinxDisplay

final class ClaudeCodeUsageClientTests: XCTestCase {
  func testAggregatesTodayAndWeekTokensAndSessions() throws {
    let now = Date()
    let projectsRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-usage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: projectsRoot) }

    let projectDir = projectsRoot.appendingPathComponent("-Users-demo-project")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let lines = [
      assistantLine(
        sessionId: "s1", model: "claude-opus-4-8",
        timestamp: now.addingTimeInterval(-60),
        input: 100, output: 50, cacheCreation: 10, cacheRead: 20),
      assistantLine(
        sessionId: "s2", model: "claude-sonnet-5",
        timestamp: now.addingTimeInterval(-120),
        input: 200, output: 100, cacheCreation: 0, cacheRead: 0),
      assistantLine(
        sessionId: "s3", model: "claude-haiku-4-5",
        timestamp: now.addingTimeInterval(-2 * 24 * 60 * 60),
        input: 1000, output: 500, cacheCreation: 0, cacheRead: 0),
      assistantLine(
        sessionId: "s4", model: "claude-haiku-4-5",
        timestamp: now.addingTimeInterval(-10 * 24 * 60 * 60),
        input: 9999, output: 0, cacheCreation: 0, cacheRead: 0),
      #"{"type":"user","message":{"content":"hi"},"sessionId":"s1"}"#,
      "not-json-at-all",
    ]
    try (lines.joined(separator: "\n") + "\n").write(
      to: projectDir.appendingPathComponent("session.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let snapshot = try ClaudeCodeUsageClient.aggregate(projectsURL: projectsRoot, now: now)

    XCTAssertEqual(snapshot.todayTokens, 450)  // 150 + 300 (input + output only)
    XCTAssertEqual(snapshot.weekTokens, 1950)  // 450 + 1500
    XCTAssertEqual(snapshot.todaySessions, 2)
    XCTAssertEqual(snapshot.model, "claude-opus-4-8")
    XCTAssertEqual(
      snapshot.lastActiveDate,
      ClaudeCodeUsageClient.parseDate(iso(now.addingTimeInterval(-60)))
    )
  }

  func testMissingProjectsDirectoryReturnsZeroSnapshot() throws {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-usage-missing-\(UUID().uuidString)", isDirectory: true)

    let snapshot = try ClaudeCodeUsageClient.aggregate(projectsURL: missing, now: Date())

    XCTAssertEqual(snapshot.todayTokens, 0)
    XCTAssertEqual(snapshot.weekTokens, 0)
    XCTAssertEqual(snapshot.todaySessions, 0)
    XCTAssertNil(snapshot.model)
    XCTAssertNil(snapshot.lastActiveDate)
  }

  func testSkipsFilesOlderThanWeekByModificationDate() throws {
    let now = Date()
    let projectsRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-usage-stale-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: projectsRoot) }

    let projectDir = projectsRoot.appendingPathComponent("-Users-demo-project")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let oldFile = projectDir.appendingPathComponent("old.jsonl")
    try assistantLine(
      sessionId: "s1", model: "claude-opus-4-8",
      timestamp: now.addingTimeInterval(-60),
      input: 500, output: 0, cacheCreation: 0, cacheRead: 0
    ).write(to: oldFile, atomically: true, encoding: .utf8)

    // Backdate the file modification time to 10 days ago so it is skipped.
    let oldDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
    try FileManager.default.setAttributes(
      [.modificationDate: oldDate],
      ofItemAtPath: oldFile.path
    )

    let snapshot = try ClaudeCodeUsageClient.aggregate(projectsURL: projectsRoot, now: now)
    XCTAssertEqual(snapshot.todayTokens, 0)
    XCTAssertEqual(snapshot.todaySessions, 0)
  }

  func testTokenFormatter() {
    XCTAssertEqual(ClaudeCodeTokenFormatter.string(from: 0), "0")
    XCTAssertEqual(ClaudeCodeTokenFormatter.string(from: 999), "999")
    XCTAssertEqual(ClaudeCodeTokenFormatter.string(from: 1_000), "1.0k")
    XCTAssertEqual(ClaudeCodeTokenFormatter.string(from: 18_432), "18.4k")
    XCTAssertEqual(ClaudeCodeTokenFormatter.string(from: 1_264_500), "1.3M")
  }

  // MARK: - Helpers

  private func assistantLine(
    sessionId: String,
    model: String,
    timestamp: Date,
    input: Int,
    output: Int,
    cacheCreation: Int,
    cacheRead: Int
  ) -> String {
    let payload: [String: Any] = [
      "type": "assistant",
      "sessionId": sessionId,
      "timestamp": iso(timestamp),
      "message": [
        "model": model,
        "usage": [
          "input_tokens": input,
          "output_tokens": output,
          "cache_creation_input_tokens": cacheCreation,
          "cache_read_input_tokens": cacheRead,
        ],
      ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return String(data: data, encoding: .utf8)!
  }

  private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
