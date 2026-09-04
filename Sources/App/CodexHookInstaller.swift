import Foundation

enum CodexHookInstallationState: Equatable {
  case notInstalled
  case configured
  case active(Date)
  case failed(String)

  var title: String {
    switch self {
    case .notInstalled: return "未安装"
    case .configured: return "已配置"
    case .active: return "已生效"
    case .failed: return "安装失败"
    }
  }

  var isConfigured: Bool {
    switch self {
    case .configured, .active: return true
    case .notInstalled, .failed: return false
    }
  }
}

struct CodexHookInstaller {
  private static let handlerFilename = "codex-linx-activity-hook.py"
  private static let legacyHandlerFilename = "codex-linx-activity-hook.sh"

  private let configURL: URL
  private let handlerURL: URL
  private let fileManager: FileManager

  init(
    configURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/hooks.json"),
    handlerURL: URL = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CodexLinxDisplay/hooks")
      .appendingPathComponent(CodexHookInstaller.handlerFilename),
    fileManager: FileManager = .default
  ) {
    self.configURL = configURL
    self.handlerURL = handlerURL
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
    return .configured
  }

  func install() throws {
    let expectedHandlerData = Data(Self.handlerScript.utf8)
    if (try? Data(contentsOf: handlerURL)) != expectedHandlerData {
      try fileManager.createDirectory(
        at: handlerURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try expectedHandlerData.write(to: handlerURL, options: .atomic)
      try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: handlerURL.path
      )
    }

    try fileManager.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var root: [String: Any] = [:]
    if fileManager.fileExists(atPath: configURL.path) {
      let existingData = try Data(contentsOf: configURL)
      guard
        let existingRoot = try JSONSerialization.jsonObject(with: existingData)
          as? [String: Any]
      else {
        throw CodexHookInstallerError.invalidConfiguration
      }
      root = existingRoot
    }

    // Codex records trust against the hook definition's hash. Rewriting an
    // already-correct hooks.json can make trusted hooks require review again,
    // even when only the handler script needed an update.
    guard !containsCurrentHandler(in: root) else { return }

    if fileManager.fileExists(atPath: configURL.path) {
      try createBackupIfNeeded()
    }

    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for definition in hookDefinitions {
      var groups = hooks[definition.event] as? [Any] ?? []
      groups.removeAll(where: groupContainsInstalledHandler)
      groups.append(definition.group)
      hooks[definition.event] = groups
    }
    root["hooks"] = hooks

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

  private var hookDefinitions: [(event: String, group: [String: Any])] {
    ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
      .map { hookDefinition(event: $0) }
  }

  private func hookDefinition(event: String) -> (event: String, group: [String: Any]) {
    (
      event,
      [
        "hooks": [
          [
            "type": "command",
            "command": "/usr/bin/python3 \(shellQuoted(handlerURL.path))",
            "timeout": 2,
          ]
        ]
      ]
    )
  }

  private func containsInstalledHandler(in root: [String: Any]) -> Bool {
    containsCurrentHandler(in: root)
  }

  private func containsCurrentHandler(in root: [String: Any]) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any] else { return false }
    let installedEvents = Set(
      hooks.compactMap { key, value in
        let groups = value as? [Any] ?? []
        return groups.contains(where: groupContainsCurrentHandler) ? key : nil
      }
    )
    return installedEvents.isSuperset(
      of: ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
    )
  }

  private func groupContainsCurrentHandler(_ value: Any) -> Bool {
    guard
      let group = value as? [String: Any],
      let handlers = group["hooks"] as? [[String: Any]]
    else {
      return false
    }
    return handlers.contains {
      guard let command = $0["command"] as? String else { return false }
      return command.contains(Self.handlerFilename)
    }
  }

  private func groupContainsInstalledHandler(_ value: Any) -> Bool {
    guard
      let group = value as? [String: Any],
      let handlers = group["hooks"] as? [[String: Any]]
    else {
      return false
    }
    return handlers.contains {
      guard let command = $0["command"] as? String else { return false }
      return command.contains(Self.handlerFilename)
        || command.contains(Self.legacyHandlerFilename)
    }
  }

  private func createBackupIfNeeded() throws {
    let backupURL = configURL.appendingPathExtension("codex-linx-backup")
    guard !fileManager.fileExists(atPath: backupURL.path) else { return }
    try fileManager.copyItem(at: configURL, to: backupURL)
  }

  private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  private static let handlerScript = #"""
#!/usr/bin/python3
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

SCHEMA_VERSION = 2
ACTIVITY_DIR = Path(
    os.environ.get(
        "CODEX_LINX_ACTIVITY_DIR",
        str(Path.home() / "Library" / "Application Support" / "CodexLinxDisplay" / "activity"),
    )
)


def response_failed(value):
    if isinstance(value, dict):
        for key in ("isError", "is_error", "failed"):
            if value.get(key) is True:
                return True
        for key in ("exit_code", "exitCode", "status_code", "statusCode"):
            code = value.get(key)
            if isinstance(code, int) and not isinstance(code, bool) and code != 0:
                return True
        if value.get("success") is False or value.get("ok") is False:
            return True
        return any(response_failed(item) for item in value.values())
    if isinstance(value, list):
        return any(response_failed(item) for item in value)
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                return response_failed(json.loads(stripped))
            except json.JSONDecodeError:
                pass
        return bool(
            re.search(r'"(?:exit_code|exitCode)"\s*:\s*[1-9]\d*', value)
            or re.search(r"\bProcess exited with (?:code|status) [1-9]\d*\b", value)
        )
    return False


def main():
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0
    if not isinstance(event, dict):
        return 0

    event_name = event.get("hook_event_name")
    session_id = event.get("session_id")
    if not isinstance(event_name, str) or not isinstance(session_id, str) or not session_id:
        return 0

    state_by_event = {
        "UserPromptSubmit": "running",
        "PermissionRequest": "awaitingAuthorization",
        "PostToolUse": "running",
        "Stop": "finished",
    }
    if event_name == "SessionEnd":
        state = None
    else:
        state = state_by_event.get(event_name)
        if state is None:
            return 0
        if event_name == "PostToolUse" and response_failed(event.get("tool_response")):
            state = "toolFailed"

    ACTIVITY_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(str(ACTIVITY_DIR), 0o700)
    filename = hashlib.sha256(session_id.encode("utf-8")).hexdigest() + ".json"
    destination = ACTIVITY_DIR / filename

    if event_name == "SessionEnd":
        try:
            destination.unlink()
        except FileNotFoundError:
            pass
        return 0

    if event_name == "Stop":
        try:
            with destination.open("r", encoding="utf-8") as handle:
                previous_state = json.load(handle).get("state")
            if previous_state in ("awaitingAuthorization", "toolFailed"):
                state = previous_state
        except (OSError, AttributeError, json.JSONDecodeError):
            pass

    record = {
        "schemaVersion": SCHEMA_VERSION,
        "sessionId": session_id,
        "eventName": event_name,
        "state": state,
        "updatedAt": time.time(),
    }
    turn_id = event.get("turn_id")
    if isinstance(turn_id, str) and turn_id:
        record["turnId"] = turn_id

    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=str(ACTIVITY_DIR),
            prefix=".codex-activity-",
            suffix=".json",
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
            os.chmod(handle.name, 0o600)
            json.dump(record, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))
        os.chmod(str(destination), 0o600)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""#
}

enum CodexHookInstallerError: LocalizedError {
  case invalidConfiguration

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "现有 ~/.codex/hooks.json 不是有效的 JSON，未进行修改。"
    }
  }
}
