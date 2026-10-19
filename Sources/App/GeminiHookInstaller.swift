import Foundation

enum GeminiHookInstallerError: LocalizedError {
  case invalidConfiguration
  case handlerWriteFailed
  case configurationWriteFailed

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "Gemini Hook 配置文件不是有效的 JSON 对象。"
    case .handlerWriteFailed:
      return "写入 Gemini Hook 脚本失败。"
    case .configurationWriteFailed:
      return "写入 Gemini Hook 配置文件失败。"
    }
  }
}

struct GeminiHookInstaller {
  private static let handlerFilename = "gemini-activity-hook.py"
  private static let hookName = "codex-linx-gemini-activity"

  private let configURL: URL
  private let handlerURL: URL
  private let activityDirectoryURL: URL
  private let fileManager: FileManager

  init(
    configURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gemini/config/hooks.json"),
    handlerURL: URL = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CodexLinxDisplay/hooks")
      .appendingPathComponent(GeminiHookInstaller.handlerFilename),
    activityDirectoryURL: URL = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CodexLinxDisplay/gemini-activity", isDirectory: true),
    fileManager: FileManager = .default
  ) {
    self.configURL = configURL
    self.handlerURL = handlerURL
    self.activityDirectoryURL = activityDirectoryURL
    self.fileManager = fileManager
  }

  func installationState() -> CodexHookInstallationState {
    guard
      let handlerData = try? Data(contentsOf: handlerURL),
      handlerData == Data(Self.handlerScript.utf8),
      let data = try? Data(contentsOf: configURL),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      containsInstalledHandler(in: root)
    else {
      return .notInstalled
    }

    if let latestActivityDate = latestActivityDate() {
      return .active(latestActivityDate)
    }
    return .configured
  }

  func install() throws {
    try fileManager.createDirectory(
      at: handlerURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(Self.handlerScript.utf8).write(to: handlerURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: handlerURL.path
    )

    try fileManager.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var root: [String: Any] = [:]
    if fileManager.fileExists(atPath: configURL.path) {
      let existingData = try Data(contentsOf: configURL)
      guard
        let existingRoot = try? JSONSerialization.jsonObject(with: existingData)
          as? [String: Any]
      else {
        throw GeminiHookInstallerError.invalidConfiguration
      }
      root = existingRoot
      try createBackupIfNeeded()
    }

    let command = "/usr/bin/python3 \(shellQuoted(handlerURL.path))"
    let hookSpec: [String: Any] = [
      "enabled": true,
      "SessionStart": [
        ["type": "command", "command": command, "timeout": 5]
      ],
      "PreInvocation": [
        ["type": "command", "command": command, "timeout": 5]
      ],
      "PreToolUse": [
        [
          "matcher": "*",
          "hooks": [
            ["type": "command", "command": command, "timeout": 5]
          ]
        ]
      ],
      "PostToolUse": [
        [
          "matcher": "*",
          "hooks": [
            ["type": "command", "command": command, "timeout": 5]
          ]
        ]
      ],
      "Stop": [
        ["type": "command", "command": command, "timeout": 5]
      ]
    ]

    root[Self.hookName] = hookSpec

    let data = try JSONSerialization.data(
      withJSONObject: root,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try data.write(to: configURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: configURL.path
    )
  }

  private func containsInstalledHandler(in root: [String: Any]) -> Bool {
    guard let hook = root[Self.hookName] as? [String: Any] else { return false }
    if (hook["enabled"] as? Bool) == false { return false }
    guard let stopList = hook["Stop"] as? [[String: Any]],
          let first = stopList.first,
          let command = first["command"] as? String
    else { return false }
    return command.contains(Self.handlerFilename)
  }

  private func createBackupIfNeeded() throws {
    let backupURL = configURL.appendingPathExtension("codex-linx-backup")
    guard !fileManager.fileExists(atPath: backupURL.path) else { return }
    try fileManager.copyItem(at: configURL, to: backupURL)
  }

  private func latestActivityDate() -> Date? {
    let urls = (try? fileManager.contentsOfDirectory(
      at: activityDirectoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    return urls.compactMap {
      try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }.max()
  }

  private func shellQuoted(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static let handlerScript = """
#!/usr/bin/env python3
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

SCHEMA_VERSION = 2
ACTIVITY_DIR = Path(
    os.environ.get(
        "GEMINI_LINX_ACTIVITY_DIR",
        str(Path.home() / "Library" / "Application Support" / "CodexLinxDisplay" / "gemini-activity"),
    )
)


def main():
    try:
        raw_input = sys.stdin.read()
        event = json.loads(raw_input) if raw_input.strip() else {}
    except Exception:
        event = {}

    try:
        process_event(event)
    except Exception:
        pass

    # Gemini hook requires a JSON response on stdout
    print("{}")
    return 0


def process_event(event):
    if not isinstance(event, dict):
        return

    session_id = (
        event.get("conversationId")
        or event.get("conversation_id")
        or event.get("sessionId")
        or event.get("session_id")
    )
    if not session_id or not isinstance(session_id, str):
        return

    hook_event = event.get("hookEvent") or event.get("hook_event_name") or event.get("event")

    tool_name = event.get("toolName") or event.get("tool_name") or event.get("matcher")
    if not tool_name and isinstance(event.get("toolCall"), dict):
        tool_name = event["toolCall"].get("name")

    state = "running"
    if tool_name == "ask_question":
        state = "awaitingUserInput"
    elif hook_event in ("Stop", "stop"):
        state = "finished"
    elif hook_event in ("SessionEnd", "session_end"):
        state = None
    elif event.get("isError") or event.get("status") == "ERROR":
        state = "toolFailed"

    ACTIVITY_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(str(ACTIVITY_DIR), 0o700)
    except OSError:
        pass

    filename = hashlib.sha256(session_id.encode("utf-8")).hexdigest() + ".json"
    destination = ACTIVITY_DIR / filename

    if state is None:
        try:
            destination.unlink()
        except FileNotFoundError:
            pass
        return

    record = {
        "schemaVersion": SCHEMA_VERSION,
        "sessionId": session_id,
        "eventName": hook_event or "hook",
        "state": state,
        "updatedAt": time.time(),
        "source": "gemini",
    }

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=str(ACTIVITY_DIR),
            prefix=".gemini-activity-",
            suffix=".json",
            delete=False,
        ) as handle:
            json.dump(record, handle, ensure_ascii=False, separators=(",", ":"))
            temp_path = Path(handle.name)
        temp_path.replace(destination)
    except Exception:
        pass


if __name__ == "__main__":
    main()
"""
}
