import Foundation
import XCTest

@testable import CodexLinxDisplay

final class GrokActivityTests: XCTestCase {
  func testOpenCliWithoutTurnIsIdle() {
    XCTAssertEqual(
      GrokActivityInterpreter.state(event: nil, processLive: true),
      .idle
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .turnStarted, date: Date()),
        processLive: false
      ),
      .idle
    )
  }

  func testTurnEventsMapToTrafficLights() {
    let now = Date()
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .turnStarted, date: now),
        processLive: true,
        now: now
      ),
      .running
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .inProgress, date: now),
        processLive: true,
        now: now
      ),
      .running
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .permissionRequested, date: now),
        processLive: true,
        now: now
      ),
      .awaitingAuthorization
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .turnEnded(outcome: "completed"), date: now),
        processLive: true,
        now: now
      ),
      .finished
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(
          kind: .turnEnded(outcome: "completed"),
          date: now.addingTimeInterval(-30)
        ),
        processLive: true,
        now: now
      ),
      .idle
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .turnEnded(outcome: "error"), date: now),
        processLive: true,
        now: now
      ),
      .toolFailed
    )
    XCTAssertEqual(
      GrokActivityInterpreter.state(
        event: GrokSessionEvent(kind: .toolCompleted(outcome: "error"), date: now),
        processLive: true,
        now: now
      ),
      .toolFailed
    )
  }

  func testClassifyIgnoresSessionSetupEvents() {
    XCTAssertNil(GrokActivityInterpreter.classify(line: #"{"ts":"2026-09-07T07:00:00.000Z","type":"mcp_init_completed"}"#))
    XCTAssertEqual(
      GrokActivityInterpreter.classify(line: #"{"ts":"2026-09-07T07:00:00.000Z","type":"turn_started"}"#)?.kind,
      .turnStarted
    )
    XCTAssertEqual(
      GrokActivityInterpreter.classify(
        line: #"{"ts":"2026-09-07T07:00:01.000Z","type":"turn_ended","outcome":"completed"}"#
      )?.kind,
      .turnEnded(outcome: "completed")
    )
    XCTAssertEqual(
      GrokActivityInterpreter.classify(
        line: #"{"ts":"2026-09-07T07:00:01.000Z","type":"permission_requested","tool_name":"grep"}"#
      )?.kind,
      .permissionRequested
    )
    XCTAssertEqual(
      GrokActivityInterpreter.classify(
        line: #"{"ts":"2026-09-07T07:00:01.000Z","type":"phase_changed","phase":"streaming_text"}"#
      )?.kind,
      .inProgress
    )
  }

  func testAggregatePrefersFailureThenAuthorizationThenRunning() {
    XCTAssertEqual(
      GrokActivityInterpreter.aggregate([.idle, .running, .toolFailed]),
      .toolFailed
    )
    XCTAssertEqual(
      GrokActivityInterpreter.aggregate([.finished, .awaitingAuthorization, .running]),
      .awaitingAuthorization
    )
    XCTAssertEqual(
      GrokActivityInterpreter.aggregate([.idle, .finished, .running]),
      .running
    )
    XCTAssertEqual(
      GrokActivityInterpreter.aggregate([.idle, .finished]),
      .finished
    )
  }

  @MainActor
  func testMonitorUsesSessionEventsNotJustLiveProcess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = root.appendingPathComponent("sessions")
    let cwd = "/Users/pyvio/Documents/other-code/CodexLinxDisplay"
    let sessionID = "session-test"
    let encoded = try XCTUnwrap(
      cwd.addingPercentEncoding(
        withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
      )
    )
    let sessionDir = sessions.appendingPathComponent(encoded).appendingPathComponent(sessionID)
    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let pid = Int(ProcessInfo.processInfo.processIdentifier)
    let active = root.appendingPathComponent("active_sessions.json")
    try Data(
      """
      [{"session_id":"\(sessionID)","pid":\(pid),"cwd":"\(cwd)","opened_at":"2026-09-07T07:00:00.000Z"}]
      """.utf8
    ).write(to: active)

    let events = sessionDir.appendingPathComponent("events.jsonl")
    let monitor = GrokActivityMonitor(
      activeSessionsURL: active,
      sessionsDirectoryURL: sessions,
      completedHoldInterval: 10
    )

    try Data(#"{"ts":"2026-09-07T07:00:00.000Z","type":"mcp_init_completed"}"#.utf8).write(to: events)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .idle)

    try Data(
      """
      {"ts":"2026-09-07T07:00:00.000Z","type":"mcp_init_completed"}
      {"ts":"2026-09-07T07:00:01.000Z","type":"turn_started"}
      """.utf8
    ).write(to: events)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .running)

    try Data(
      """
      {"ts":"2026-09-07T07:00:01.000Z","type":"turn_started"}
      {"ts":"2026-09-07T07:00:02.000Z","type":"permission_requested","tool_name":"grep"}
      """.utf8
    ).write(to: events)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .awaitingAuthorization)

    let ended = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
    try Data(
      """
      {"ts":"2026-09-07T07:00:01.000Z","type":"turn_started"}
      {"ts":"\(ended)","type":"turn_ended","outcome":"completed"}
      """.utf8
    ).write(to: events)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .idle)
  }
}
