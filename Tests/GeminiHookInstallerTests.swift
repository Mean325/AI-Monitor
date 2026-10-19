import Foundation
import XCTest

@testable import CodexLinxDisplay

final class GeminiHookInstallerTests: XCTestCase {
  func testInstallsHookAndPreservesExistingConfig() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemini-hook-test-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".gemini/config/hooks.json")
    let handlerURL = root.appendingPathComponent("hooks/gemini-activity-hook.py")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let existing: [String: Any] = [
      "my-custom-hook": [
        "SessionStart": [["command": "/usr/bin/true"]]
      ]
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: configURL)

    let installer = GeminiHookInstaller(configURL: configURL, handlerURL: handlerURL)
    try installer.install()

    XCTAssertEqual(installer.installationState(), .configured)
    XCTAssertTrue(FileManager.default.fileExists(atPath: handlerURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.appendingPathExtension("codex-linx-backup").path))

    let installedData = try Data(contentsOf: configURL)
    let installedRoot = try XCTUnwrap(
      JSONSerialization.jsonObject(with: installedData) as? [String: Any]
    )

    // Existing hook should be preserved
    XCTAssertNotNil(installedRoot["my-custom-hook"])

    // Codex Linx Gemini hook should be configured
    let geminiHook = try XCTUnwrap(installedRoot["codex-linx-gemini-activity"] as? [String: Any])
    XCTAssertNotNil(geminiHook["SessionStart"])
    XCTAssertNotNil(geminiHook["PreInvocation"])
    XCTAssertNotNil(geminiHook["PreToolUse"])
    XCTAssertNotNil(geminiHook["PostToolUse"])
    XCTAssertNotNil(geminiHook["Stop"])
  }

  func testHookScriptExecutesAndOutputsValidJson() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemini-hook-exec-\(UUID().uuidString)", isDirectory: true)
    let configURL = root.appendingPathComponent(".gemini/config/hooks.json")
    let handlerURL = root.appendingPathComponent("hooks/gemini-activity-hook.py")
    let activityDir = root.appendingPathComponent("activity", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = GeminiHookInstaller(configURL: configURL, handlerURL: handlerURL)
    try installer.install()

    // Run python script with PreToolUse (ask_question)
    let inputPayload = """
    {
      "hook_event_name": "PreToolUse",
      "conversation_id": "test-conv-123",
      "tool_name": "ask_question"
    }
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [handlerURL.path]

    var env = ProcessInfo.processInfo.environment
    env["GEMINI_LINX_ACTIVITY_DIR"] = activityDir.path
    process.environment = env

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe

    try process.run()
    try stdinPipe.fileHandleForWriting.write(contentsOf: Data(inputPayload.utf8))
    try stdinPipe.fileHandleForWriting.close()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stdoutString = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertEqual(stdoutString, "{}")

    // Verify activity record file was written
    let activityFiles = try FileManager.default.contentsOfDirectory(at: activityDir, includingPropertiesForKeys: nil)
    XCTAssertFalse(activityFiles.isEmpty)

    let recordData = try Data(contentsOf: activityFiles[0])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let record = try decoder.decode(CodexActivityRecord.self, from: recordData)
    XCTAssertEqual(record.state, .awaitingUserInput)
    XCTAssertEqual(record.source, "gemini")
    XCTAssertEqual(record.sessionID, "test-conv-123")
  }
}
