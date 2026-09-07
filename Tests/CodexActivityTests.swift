import Foundation
import XCTest

@testable import CodexLinxDisplay

final class CodexActivityTests: XCTestCase {
  @MainActor
  func testQuotaStopTurnsRedAndNewTaskRecovers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = sessions.appendingPathComponent("session.jsonl")
    let date = ISO8601DateFormatter().string(from: Date())
    let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let start = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"task_started","turn_id":"1"}}"#
    func quota(credits: Bool, unlimited: Bool = false, resetAt: Int) -> String {
      #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":100,"resets_at":\#(resetAt)},"credits":{"has_credits":\#(credits),"unlimited":\#(unlimited)}}}}"#
    }
    let monitor = CodexActivityMonitor(directoryURL: root.appendingPathComponent("hooks"),
      sessionsDirectoryURL: sessions)
    try Data((start + "\n" + quota(credits: false, resetAt: reset) + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: monitor.state, mode: .codex), 0)
    let recovered = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":0},"secondary":{"used_percent":43},"credits":{"has_credits":false}}}}"#
    try Data((start + "\n" + quota(credits: false, resetAt: reset) + "\n" + recovered + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .running)
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: monitor.state, mode: .codex), 1)
    for line in [quota(credits: true, resetAt: reset),
                 quota(credits: false, unlimited: true, resetAt: reset)] {
      try Data((start + "\n" + line + "\n").utf8).write(to: url)
      monitor.refresh()
      XCTAssertEqual(monitor.state, .running)
    }
    try Data((start + "\n" + quota(credits: false, resetAt: 1) + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .idle)
    try Data((start + "\n" + quota(credits: false, resetAt: reset) + "\n" + start + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: monitor.state, mode: .codex), 0)
    let error = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"error","message":"You have hit your usage limit"}}"#
    try Data((start + "\n" + error + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)
  }

  @MainActor
  func testExhaustedQuotaStaysRedThroughLaterTaskEvents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = sessions.appendingPathComponent("session.jsonl")
    let date = ISO8601DateFormatter().string(from: Date())
    let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let start = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"task_started","turn_id":"1"}}"#
    let complete = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"task_complete","turn_id":"1"}}"#
    let exhausted = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":36.0,"resets_at":\#(reset)},"secondary":{"used_percent":100.0,"resets_at":\#(reset)},"credits":{"has_credits":false,"unlimited":false}}}}"#
    let premium = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":null,"secondary":null,"credits":{"has_credits":false,"unlimited":false}}}}"#
    let missingCredits = #"{"timestamp":"\#(date)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":100.0,"resets_at":\#(reset)}}}}"#
    let monitor = CodexActivityMonitor(
      directoryURL: root.appendingPathComponent("hooks"),
      sessionsDirectoryURL: sessions
    )

    try Data((start + "\n" + exhausted + "\n" + premium + "\n" + complete + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: monitor.state, mode: .codex), 0)

    try Data((start + "\n" + exhausted + "\n" + premium + "\n" + complete + "\n" + start + "\n").utf8)
      .write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)

    try Data((start + "\n" + missingCredits + "\n" + complete + "\n").utf8).write(to: url)
    monitor.refresh()
    XCTAssertEqual(monitor.state, .toolFailed)
  }

  func testTrafficLightPriorityIsFailureThenAuthorizationThenRunningThenFinished() {
    let now = Date()
    let records = [
      CodexActivityRecord(
        schemaVersion: 2,
        sessionID: "finished",
        turnID: "1",
        eventName: "Stop",
        state: .finished,
        updatedAt: now
      ),
      CodexActivityRecord(
        schemaVersion: 2,
        sessionID: "running",
        turnID: "2",
        eventName: "UserPromptSubmit",
        state: .running,
        updatedAt: now
      ),
      CodexActivityRecord(
        schemaVersion: 2,
        sessionID: "authorization",
        turnID: "3",
        eventName: "PermissionRequest",
        state: .awaitingAuthorization,
        updatedAt: now
      ),
      CodexActivityRecord(
        schemaVersion: 2,
        sessionID: "failed",
        turnID: "4",
        eventName: "PostToolUse",
        state: .toolFailed,
        updatedAt: now
      ),
    ]

    XCTAssertEqual(CodexActivityReducer.aggregate(records, now: now), .toolFailed)
    XCTAssertEqual(
      CodexActivityReducer.aggregate(Array(records.prefix(3)), now: now),
      .awaitingAuthorization
    )
    XCTAssertEqual(CodexActivityReducer.aggregate(Array(records.prefix(2)), now: now), .running)
    XCTAssertEqual(CodexActivityReducer.aggregate(Array(records.prefix(1)), now: now), .finished)
    XCTAssertEqual(CodexActivityReducer.aggregate([], now: now), .idle)
  }

  func testStaleActiveStateFallsBackToIdle() {
    let now = Date()
    let staleRecord = CodexActivityRecord(
      schemaVersion: 2,
      sessionID: "stale",
      turnID: "1",
      eventName: "UserPromptSubmit",
      state: .running,
      updatedAt: now.addingTimeInterval(-120)
    )

    XCTAssertEqual(
      CodexActivityReducer.aggregate([staleRecord], now: now, staleInterval: 60),
      .idle
    )
  }

  func testCompletedStateFallsBackToIdleAfterHoldInterval() {
    let now = Date()
    let record = CodexActivityRecord(
      schemaVersion: 2,
      sessionID: "completed",
      turnID: "1",
      eventName: "Stop",
      state: .finished,
      updatedAt: now.addingTimeInterval(-11)
    )

    XCTAssertEqual(
      CodexActivityReducer.aggregate([record], now: now, completedHoldInterval: 10),
      .idle
    )
  }

  @MainActor
  func testMonitorReadsAtomicActivityRecords() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-activity-monitor-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let monitor = CodexActivityMonitor(directoryURL: directory, sessionsDirectoryURL: nil)
    monitor.start()
    XCTAssertEqual(monitor.state, .idle)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let record = CodexActivityRecord(
      schemaVersion: 2,
      sessionID: "session",
      turnID: "turn",
      eventName: "UserPromptSubmit",
      state: .running,
      updatedAt: Date()
    )
    let data = try encoder.encode(record)
    try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)

    monitor.refresh()
    XCTAssertEqual(monitor.state, .running)
    monitor.stop()
  }

  @MainActor
  func testMonitorAutomaticallyPublishesAtomicActivityRecords() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-activity-monitor-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let monitor = CodexActivityMonitor(directoryURL: directory, sessionsDirectoryURL: nil)
    let stateChanged = expectation(description: "activity state changed")
    monitor.onStateChange = { state in
      if state == .running {
        stateChanged.fulfill()
      }
    }
    monitor.start()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let record = CodexActivityRecord(
      schemaVersion: 2,
      sessionID: "session",
      turnID: "turn",
      eventName: "UserPromptSubmit",
      state: .running,
      updatedAt: Date()
    )
    try encoder.encode(record).write(
      to: directory.appendingPathComponent("session.json"),
      options: .atomic
    )

    await fulfillment(of: [stateChanged], timeout: 2)
    XCTAssertEqual(monitor.state, .running)
    monitor.stop()
  }

  @MainActor
  func testMonitorFallsBackToCodexDesktopSessionLifecycleEvents() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-session-monitor-\(UUID().uuidString)", isDirectory: true)
    let activityDirectory = root.appendingPathComponent("activity", isDirectory: true)
    let sessionsDirectory = root.appendingPathComponent("sessions/2026/08/03", isDirectory: true)
    let sessionURL = sessionsDirectory.appendingPathComponent("rollout-session.jsonl")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: sessionsDirectory,
      withIntermediateDirectories: true
    )
    let startedAt = ISO8601DateFormatter().string(from: Date())
    let started = #"{"timestamp":"\#(startedAt)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#
    try Data("\(started)\n".utf8).write(to: sessionURL)

    let monitor = CodexActivityMonitor(
      directoryURL: activityDirectory,
      sessionsDirectoryURL: root.appendingPathComponent("sessions", isDirectory: true)
    )
    monitor.start()
    XCTAssertEqual(monitor.state, .running)

    let completedAt = ISO8601DateFormatter().string(from: Date())
    let completed = #"{"timestamp":"\#(completedAt)","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#
    let handle = try FileHandle(forWritingTo: sessionURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\(completed)\n".utf8))
    try handle.close()

    monitor.refresh()
    XCTAssertEqual(monitor.state, .finished)
    monitor.stop()
  }

  func testHookInstallerPreservesExistingHooksAndCreatesBackup() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-hook-installer-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".codex/hooks.json")
    let handlerURL = root.appendingPathComponent(
      "Library/Application Support/CodexLinxDisplay/hooks/codex-linx-activity-hook.py"
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing: [String: Any] = [
      "description": "existing hooks",
      "hooks": [
        "UserPromptSubmit": [
          [
            "hooks": [
              [
                "type": "command",
                "command": "/usr/bin/true",
              ]
            ]
          ]
        ]
      ],
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: configURL)

    let installer = CodexHookInstaller(
      configURL: configURL,
      handlerURL: handlerURL
    )
    try installer.install()

    XCTAssertEqual(installer.installationState(), .configured)
    XCTAssertTrue(FileManager.default.fileExists(atPath: handlerURL.path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: configURL.appendingPathExtension("codex-linx-backup").path
      )
    )

    let installedData = try Data(contentsOf: configURL)
    let installedRoot = try XCTUnwrap(
      JSONSerialization.jsonObject(with: installedData) as? [String: Any]
    )
    XCTAssertEqual(installedRoot["description"] as? String, "existing hooks")

    let hooks = try XCTUnwrap(installedRoot["hooks"] as? [String: Any])
    let promptGroups = try XCTUnwrap(hooks["UserPromptSubmit"] as? [Any])
    XCTAssertTrue(
      promptGroups.contains { group in
        guard
          let dictionary = group as? [String: Any],
          let handlers = dictionary["hooks"] as? [[String: Any]]
        else {
          return false
        }
        return handlers.contains { ($0["command"] as? String) == "/usr/bin/true" }
      }
    )

    let activityDirectory = root.appendingPathComponent("activity", isDirectory: true)
    func runHook(_ payload: String) throws {
      let process = Process()
      let input = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
      process.arguments = [handlerURL.path]
      process.environment = ProcessInfo.processInfo.environment.merging(
        ["CODEX_LINX_ACTIVITY_DIR": activityDirectory.path],
        uniquingKeysWith: { _, testValue in testValue }
      )
      process.standardInput = input
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      try input.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
      XCTAssertEqual(process.terminationStatus, 0)
    }

    try runHook(
      #"{"hook_event_name":"UserPromptSubmit","session_id":"session-1","turn_id":"turn-1"}"#
    )
    let stateFiles = try FileManager.default.contentsOfDirectory(
      at: activityDirectory,
      includingPropertiesForKeys: nil
    )
    XCTAssertEqual(stateFiles.filter { $0.pathExtension == "json" }.count, 1)

    let stateData = try Data(contentsOf: try XCTUnwrap(stateFiles.first))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let record = try decoder.decode(CodexActivityRecord.self, from: stateData)
    XCTAssertEqual(record.state, .running)
    XCTAssertEqual(record.sessionID, "session-1")
    XCTAssertEqual(record.eventName, "UserPromptSubmit")
    XCTAssertEqual(record.schemaVersion, 2)

    try runHook(
      #"{"hook_event_name":"PostToolUse","session_id":"session-1","turn_id":"turn-1","tool_response":{"exit_code":2}}"#
    )
    let failureData = try Data(contentsOf: try XCTUnwrap(stateFiles.first))
    let failure = try decoder.decode(CodexActivityRecord.self, from: failureData)
    XCTAssertEqual(failure.state, .toolFailed)
    XCTAssertEqual(failure.eventName, "PostToolUse")

    try runHook(
      #"{"hook_event_name":"Stop","session_id":"session-1","turn_id":"turn-1"}"#
    )
    let stoppedData = try Data(contentsOf: try XCTUnwrap(stateFiles.first))
    let stopped = try decoder.decode(CodexActivityRecord.self, from: stoppedData)
    XCTAssertEqual(stopped.state, .toolFailed)
    XCTAssertEqual(stopped.eventName, "Stop")
  }

  func testHookInstallerDetectsOutdatedHandlerAndRepairsIt() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-hook-repair-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".codex/hooks.json")
    let handlerURL = root.appendingPathComponent("hooks/codex-linx-activity-hook.py")
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = CodexHookInstaller(
      configURL: configURL,
      handlerURL: handlerURL
    )
    try installer.install()
    XCTAssertEqual(installer.installationState(), .configured)

    let configuredData = try Data(contentsOf: configURL)

    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: handlerURL, options: .atomic)
    XCTAssertEqual(installer.installationState(), .notInstalled)

    try installer.install()
    XCTAssertEqual(installer.installationState(), .configured)
    XCTAssertEqual(
      try Data(contentsOf: configURL),
      configuredData,
      "修复处理脚本时不应重写 hooks.json，否则 Codex 会要求重新信任 Hook"
    )
  }

  func testHookInstallerMigratesLegacyHandlerDefinition() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-hook-legacy-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".codex/hooks.json")
    let handlerURL = root.appendingPathComponent("hooks/codex-linx-activity-hook.py")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let legacyGroup: [String: Any] = [
      "hooks": [[
        "type": "command",
        "command": "/bin/sh /tmp/codex-linx-activity-hook.sh",
      ]]
    ]
    let events = ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
    let legacyHooks = Dictionary(uniqueKeysWithValues: events.map { ($0, [legacyGroup]) })
    try JSONSerialization.data(withJSONObject: ["hooks": legacyHooks]).write(to: configURL)

    let installer = CodexHookInstaller(configURL: configURL, handlerURL: handlerURL)
    try installer.install()

    XCTAssertEqual(installer.installationState(), .configured)
    let installedRoot = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
    )
    let hooks = try XCTUnwrap(installedRoot["hooks"] as? [String: Any])
    for event in events {
      let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
      let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }
        .compactMap { $0["command"] as? String }
      XCTAssertTrue(commands.contains { $0.contains("codex-linx-activity-hook.py") })
      XCTAssertFalse(commands.contains { $0.contains("codex-linx-activity-hook.sh") })
    }
  }
}
