import Foundation
import XCTest

@testable import CodexLinxDisplay

final class QoderUsageClientTests: XCTestCase {
  func testAggregatesTodayAndWeekPromptsAndToolCalls() throws {
    let now = Date()
    let projectsRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("qoder-usage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: projectsRoot) }

    let projectDir = projectsRoot.appendingPathComponent("-Users-demo-project")
    let transcriptDir = projectDir.appendingPathComponent("transcript", isDirectory: true)
    try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)

    let lines = [
      userLine(
        sessionId: "s1",
        timestamp: now.addingTimeInterval(-60),
        content: "Hello Qoder"
      ),
      assistantLine(
        sessionId: "s1",
        timestamp: now.addingTimeInterval(-50),
        toolUses: 2
      ),
      userLine(
        sessionId: "s2",
        timestamp: now.addingTimeInterval(-120),
        content: "Another prompt"
      ),
      userLine(
        sessionId: "s3",
        timestamp: now.addingTimeInterval(-2 * 24 * 60 * 60),
        content: "Older prompt"
      ),
      userLine(
        sessionId: "s4",
        timestamp: now.addingTimeInterval(-10 * 24 * 60 * 60),
        content: "Very old prompt"
      ),
      "not-json-at-all",
    ]
    try (lines.joined(separator: "\n") + "\n").write(
      to: transcriptDir.appendingPathComponent("session.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let snapshot = try QoderUsageClient.aggregate(projectsURL: projectsRoot, now: now)

    XCTAssertEqual(snapshot.todayPrompts, 2)  // s1 + s2
    XCTAssertEqual(snapshot.weekPrompts, 3)  // s1 + s2 + s3
    XCTAssertEqual(snapshot.todaySessions, 2)  // s1 + s2
    XCTAssertEqual(snapshot.todayToolCalls, 2)  // 2 tool uses from assistant
    XCTAssertNotNil(snapshot.lastActiveDate)
  }

  func testMissingProjectsDirectoryReturnsZeroSnapshot() throws {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("qoder-usage-missing-\(UUID().uuidString)", isDirectory: true)

    let snapshot = try QoderUsageClient.aggregate(projectsURL: missing, now: Date())

    XCTAssertEqual(snapshot.todayPrompts, 0)
    XCTAssertEqual(snapshot.weekPrompts, 0)
    XCTAssertEqual(snapshot.todaySessions, 0)
    XCTAssertEqual(snapshot.todayToolCalls, 0)
    XCTAssertNil(snapshot.lastActiveDate)
  }

  func testSkipsFilesOlderThanWeekByModificationDate() throws {
    let now = Date()
    let projectsRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("qoder-usage-stale-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: projectsRoot) }

    let projectDir = projectsRoot.appendingPathComponent("-Users-demo-project")
    let transcriptDir = projectDir.appendingPathComponent("transcript", isDirectory: true)
    try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)

    let oldFile = transcriptDir.appendingPathComponent("old.jsonl")
    try userLine(
      sessionId: "s1",
      timestamp: now.addingTimeInterval(-60),
      content: "Hello"
    ).write(to: oldFile, atomically: true, encoding: .utf8)

    // Backdate the file modification time to 10 days ago so it is skipped.
    let oldDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
    try FileManager.default.setAttributes(
      [.modificationDate: oldDate],
      ofItemAtPath: oldFile.path
    )

    let snapshot = try QoderUsageClient.aggregate(projectsURL: projectsRoot, now: now)
    XCTAssertEqual(snapshot.todayPrompts, 0)
    XCTAssertEqual(snapshot.todaySessions, 0)
  }

  func testParseDateHandlesMicrosecondFractions() {
    // Qoder writes microsecond fractions which ISO8601DateFormatter doesn't handle
    let microsecondTimestamp = "2026-07-28T07:14:12.212902Z"
    let parsed = QoderUsageClient.parseDate(microsecondTimestamp)
    XCTAssertNotNil(parsed)
  }

  // MARK: - Helpers

  private func userLine(
    sessionId: String,
    timestamp: Date,
    content: String
  ) -> String {
    let payload: [String: Any] = [
      "type": "user",
      "sessionId": sessionId,
      "timestamp": iso(timestamp),
      "message": [
        "role": "user",
        "content": content,
      ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return String(data: data, encoding: .utf8)!
  }

  private func assistantLine(
    sessionId: String,
    timestamp: Date,
    toolUses: Int
  ) -> String {
    var blocks: [[String: Any]] = []
    for _ in 0..<toolUses {
      blocks.append([
        "type": "tool_use",
        "id": UUID().uuidString,
        "name": "test_tool",
        "input": [:],
      ])
    }
    let payload: [String: Any] = [
      "type": "assistant",
      "sessionId": sessionId,
      "timestamp": iso(timestamp),
      "message": [
        "role": "assistant",
        "content": blocks,
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

final class QoderActivityInterpreterTests: XCTestCase {
  func testClassifyUserPrompt() {
    let line = """
    {"type":"user","message":{"role":"user","content":"Hello"}}
    """
    let event = QoderActivityInterpreter.classify(line: line)
    XCTAssertEqual(event, .userPrompt)
  }

  func testClassifyToolResultError() {
    let line = """
    {"type":"user","message":{"content":[{"type":"tool_result","is_error":true}]}}
    """
    let event = QoderActivityInterpreter.classify(line: line)
    XCTAssertEqual(event, .toolResult(isError: true))
  }

  func testClassifyToolUse() {
    let line = """
    {"type":"assistant","message":{"content":[{"type":"tool_use"}]}}
    """
    let event = QoderActivityInterpreter.classify(line: line)
    XCTAssertEqual(event, .toolUse)
  }

  func testClassifyAssistantText() {
    let line = """
    {"type":"assistant","message":{"content":[{"type":"text"}]}}
    """
    let event = QoderActivityInterpreter.classify(line: line)
    XCTAssertEqual(event, .assistantText)
  }

  func testStateMapping() {
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .userPrompt, age: 5),
      .running
    )
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .toolUse, age: 5),
      .running
    )
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .toolResult(isError: true), age: 5),
      .toolFailed
    )
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .assistantText, age: 5),
      .finished
    )
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .assistantText, age: 15),
      .idle
    )
    XCTAssertEqual(
      QoderActivityInterpreter.state(event: .userPrompt, age: 700),
      .idle
    )
  }
}
