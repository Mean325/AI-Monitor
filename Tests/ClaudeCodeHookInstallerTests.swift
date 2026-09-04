import Foundation
import XCTest

@testable import CodexLinxDisplay

final class ClaudeCodeHookInstallerTests: XCTestCase {
  func testPreservesExistingSettingsAndCreatesBackup() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-hook-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".claude/settings.json")
    let handlerURL = root.appendingPathComponent(
      "Library/Application Support/CodexLinxDisplay/hooks/claude-code-activity-hook.py"
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing: [String: Any] = [
      "env": ["ANTHROPIC_MODEL": "claude-opus-4-8"],
      "hooks": [
        "UserPromptSubmit": [
          ["hooks": [["type": "command", "command": "/usr/bin/true"]]]
        ]
      ],
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: configURL)

    let installer = ClaudeCodeHookInstaller(configURL: configURL, handlerURL: handlerURL)
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
    XCTAssertEqual(
      (installedRoot["env"] as? [String: Any])?["ANTHROPIC_MODEL"] as? String,
      "claude-opus-4-8"
    )

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
  }

  func testDetectsOutdatedHandlerAndRepairsIt() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-hook-repair-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".claude/settings.json")
    let handlerURL = root.appendingPathComponent("hooks/claude-code-activity-hook.py")
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = ClaudeCodeHookInstaller(configURL: configURL, handlerURL: handlerURL)
    try installer.install()
    XCTAssertEqual(installer.installationState(), .configured)

    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: handlerURL, options: .atomic)
    XCTAssertEqual(installer.installationState(), .notInstalled)

    try installer.install()
    XCTAssertEqual(installer.installationState(), .configured)
  }

  func testHookMapsClaudeEventsToActivityStates() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claude-hook-run-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".claude/settings.json")
    let handlerURL = root.appendingPathComponent("hooks/claude-code-activity-hook.py")
    let activityDirectory = root.appendingPathComponent("claude-activity", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = ClaudeCodeHookInstaller(configURL: configURL, handlerURL: handlerURL)
    try installer.install()

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    func runHook(_ payload: String) throws -> CodexActivityRecord {
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

      let stateFiles = try FileManager.default.contentsOfDirectory(
        at: activityDirectory,
        includingPropertiesForKeys: nil
      ).filter { $0.pathExtension == "json" }
      let data = try Data(contentsOf: try XCTUnwrap(stateFiles.first))
      return try decoder.decode(CodexActivityRecord.self, from: data)
    }

    let running = try runHook(
      #"{"hook_event_name":"UserPromptSubmit","session_id":"session-1","prompt_id":"prompt-1"}"#
    )
    XCTAssertEqual(running.state, .running)
    XCTAssertEqual(running.sessionID, "session-1")
    XCTAssertEqual(running.turnID, "prompt-1")
    XCTAssertEqual(running.schemaVersion, 2)

    let auth = try runHook(
      #"{"hook_event_name":"PermissionRequest","session_id":"session-1","prompt_id":"prompt-2"}"#
    )
    XCTAssertEqual(auth.state, .awaitingAuthorization)

    let failed = try runHook(
      #"{"hook_event_name":"PostToolUseFailure","session_id":"session-1","prompt_id":"prompt-3"}"#
    )
    XCTAssertEqual(failed.state, .toolFailed)

    // Stop after a failure should preserve the failed state.
    let stopped = try runHook(
      #"{"hook_event_name":"Stop","session_id":"session-1","prompt_id":"prompt-3"}"#
    )
    XCTAssertEqual(stopped.state, .toolFailed)

    // SessionEnd removes the record file.
    let endProcess = Process()
    let endInput = Pipe()
    endProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    endProcess.arguments = [handlerURL.path]
    endProcess.environment = ProcessInfo.processInfo.environment.merging(
      ["CODEX_LINX_ACTIVITY_DIR": activityDirectory.path],
      uniquingKeysWith: { _, testValue in testValue }
    )
    endProcess.standardInput = endInput
    endProcess.standardOutput = FileHandle.nullDevice
    endProcess.standardError = FileHandle.nullDevice
    try endProcess.run()
    try endInput.fileHandleForWriting.write(
      contentsOf: Data(#"{"hook_event_name":"SessionEnd","session_id":"session-1"}"#.utf8)
    )
    try endInput.fileHandleForWriting.close()
    endProcess.waitUntilExit()

    let remaining = (try? FileManager.default.contentsOfDirectory(
      at: activityDirectory,
      includingPropertiesForKeys: nil
    )) ?? []
    XCTAssertTrue(remaining.filter { $0.pathExtension == "json" }.isEmpty)
  }
}
