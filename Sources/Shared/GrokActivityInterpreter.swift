import Foundation

struct GrokSessionEvent: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case turnStarted
    case turnEnded(outcome: String?)
    case permissionRequested
    case toolStarted
    case toolCompleted(outcome: String?)
    case inProgress
  }

  let kind: Kind
  let date: Date?
}

/// Derives a traffic-light from Grok CLI `events.jsonl`.
/// A live `grok` process only means the TUI is open; task state comes from
/// the session's latest turn/tool/permission event.
enum GrokActivityInterpreter {
  static func classify(line: String) -> GrokSessionEvent? {
    guard
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
      let dictionary = object as? [String: Any],
      let type = dictionary["type"] as? String
    else { return nil }

    let date = parseDate(dictionary["ts"] as? String)
    switch type {
    case "turn_started":
      return GrokSessionEvent(kind: .turnStarted, date: date)
    case "turn_ended":
      return GrokSessionEvent(kind: .turnEnded(outcome: dictionary["outcome"] as? String), date: date)
    case "permission_requested":
      return GrokSessionEvent(kind: .permissionRequested, date: date)
    case "tool_started", "mcp_tool_call_started":
      return GrokSessionEvent(kind: .toolStarted, date: date)
    case "tool_completed", "mcp_tool_call_completed":
      return GrokSessionEvent(kind: .toolCompleted(outcome: dictionary["outcome"] as? String), date: date)
    case "permission_resolved", "phase_changed", "loop_started", "first_token":
      return GrokSessionEvent(kind: .inProgress, date: date)
    default:
      return nil
    }
  }

  static func latestEvent(in url: URL, maxBytes: Int = 256 * 1_024) -> GrokSessionEvent? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
    let readLength = min(UInt64(maxBytes), fileSize)
    try? handle.seek(toOffset: fileSize - readLength)
    guard let data = try? handle.read(upToCount: Int(readLength)) else { return nil }

    let text: String
    if let decoded = String(data: data, encoding: .utf8) {
      text = decoded
    } else if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
      text = String(data: data[(data.index(after: newline))...], encoding: .utf8) ?? ""
    } else {
      return nil
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, let event = classify(line: trimmed) else { continue }
      return event
    }
    return nil
  }

  static func state(
    event: GrokSessionEvent?,
    processLive: Bool,
    now: Date = Date(),
    completedHoldInterval: TimeInterval = 10,
    failedHoldInterval: TimeInterval = 10 * 60
  ) -> CodexActivityState {
    guard processLive else { return .idle }
    guard let event else { return .idle }

    let age = event.date.map { now.timeIntervalSince($0) } ?? 0
    switch event.kind {
    case .turnEnded(let outcome):
      if outcome == "error" {
        return age <= failedHoldInterval ? .toolFailed : .idle
      }
      return age <= completedHoldInterval ? .finished : .idle
    case .permissionRequested:
      return .awaitingAuthorization
    case .toolCompleted(let outcome) where outcome == "error":
      return .toolFailed
    case .turnStarted, .toolStarted, .toolCompleted, .inProgress:
      return .running
    }
  }

  static func aggregate(_ states: [CodexActivityState]) -> CodexActivityState {
    if states.contains(.toolFailed) { return .toolFailed }
    if states.contains(.awaitingAuthorization) { return .awaitingAuthorization }
    if states.contains(.running) { return .running }
    if states.contains(.finished) { return .finished }
    return .idle
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    if let date = fractional.date(from: value) ?? plain.date(from: value) {
      return date
    }
    return nil
  }
}

private let fractional: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

private let plain: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()
