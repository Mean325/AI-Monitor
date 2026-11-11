import Foundation
import XCTest

@testable import CodexLinxDisplay

final class GeminiActivityTests: XCTestCase {
  func testClassifyPlannerResponseWithToolRunning() {
    let line = #"{"type":"PLANNER_RESPONSE","created_at":"2026-10-19T10:00:00Z","tool_calls":[{"name":"run_command","arguments":{}}]}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .toolRunning(name: "run_command"))
    let state = GeminiActivityInterpreter.state(event: result?.event, age: 5)
    XCTAssertEqual(state, .running)
  }

  func testClassifyAskQuestionAwaitingUserInput() {
    let line = #"{"type":"PLANNER_RESPONSE","created_at":"2026-10-19T10:00:00Z","tool_calls":[{"name":"ask_question","arguments":{"question":"Proceed?"}}]}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .awaitingUserInput)
    let state = GeminiActivityInterpreter.state(event: result?.event, age: 5)
    XCTAssertEqual(state, .awaitingUserInput)
  }

  func testClassifyUserInput() {
    let line = #"{"type":"USER_INPUT","created_at":"2026-10-19T10:01:00Z","content":"Yes, proceed"}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .userPrompt)
    let state = GeminiActivityInterpreter.state(event: result?.event, age: 5)
    XCTAssertEqual(state, .running)
  }

  func testClassifyErrorMessageToolFailed() {
    let line = #"{"type":"ERROR_MESSAGE","created_at":"2026-10-19T10:02:00Z","content":"Command timed out"}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .toolFailed(message: "Command timed out"))
    let state = GeminiActivityInterpreter.state(event: result?.event, age: 5)
    XCTAssertEqual(state, .toolFailed)
  }

  func testClassifyGeneric() {
    let line = #"{"type":"GENERIC","created_at":"2026-10-19T10:03:00Z","content":"Session ended"}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .other)
  }

  func testClassifyPlannerResponseTurnCompleted() {
    let line = #"{"type":"PLANNER_RESPONSE","created_at":"2026-10-19T10:00:00Z","content":"Done!"}"#
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.event, .turnCompleted)
    let stateRecent = GeminiActivityInterpreter.state(event: result?.event, age: 5)
    XCTAssertEqual(stateRecent, .finished)
    let stateStale = GeminiActivityInterpreter.state(event: result?.event, age: 30)
    XCTAssertEqual(stateStale, .idle)
  }

  func testClassifyInvalidJson() {
    let line = "Not JSON"
    let result = GeminiActivityInterpreter.classify(line: line)
    XCTAssertNil(result)
  }

  @MainActor
  func testActivityMonitorReconcilesHookAndTranscript() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemini-activity-test-\(UUID().uuidString)", isDirectory: true)
    let activityDir = root.appendingPathComponent("activity", isDirectory: true)
    let brainDir = root.appendingPathComponent("brain", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: activityDir, withIntermediateDirectories: true)
    let convDir = brainDir.appendingPathComponent("conv-1/.system_generated/logs", isDirectory: true)
    try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

    let monitor = GeminiActivityMonitor(directoryURL: activityDir, brainURL: brainDir)

    // Write transcript entry (running with tool)
    let transcriptFile = convDir.appendingPathComponent("transcript.jsonl")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let transcriptLine = #"{"type":"USER_INPUT","created_at":"\#(timestamp)","content":"Do something"}"# + "\n"
    try transcriptLine.write(to: transcriptFile, atomically: true, encoding: .utf8)

    monitor.refresh()
    XCTAssertEqual(monitor.state, .running)

    // Hook event arrives later with newer timestamp
    let hookRecord = CodexActivityRecord(
      schemaVersion: 2,
      sessionID: "conv-1",
      turnID: nil,
      eventName: "Stop",
      state: .finished,
      updatedAt: Date().addingTimeInterval(10),
      source: "gemini"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let hookData = try encoder.encode(hookRecord)
    try hookData.write(to: activityDir.appendingPathComponent("hook-1.json"))

    monitor.refresh()
    XCTAssertEqual(monitor.state, .finished)
  }
}
