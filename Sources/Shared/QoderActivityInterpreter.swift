import Foundation

enum QoderTranscriptTailEvent: Equatable, Sendable {
  case userPrompt
  case toolUse
  case toolResult(isError: Bool)
  case assistantText
  case thinking
  case other
}

/// Derives a traffic-light activity state from the newest entry of a Qoder
/// transcript. Qoder has no hook mechanism, so the state is inferred from the
/// session log that Qoder itself keeps appending to.
enum QoderActivityInterpreter {
  static func classify(line: String) -> QoderTranscriptTailEvent? {
    guard
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
      let dictionary = object as? [String: Any],
      let type = dictionary["type"] as? String
    else { return nil }

    let message = dictionary["message"] as? [String: Any]

    switch type {
    case "user":
      if message?["content"] is String { return .userPrompt }
      let blocks = message?["content"] as? [[String: Any]] ?? []
      if let result = blocks.last(where: { ($0["type"] as? String) == "tool_result" }) {
        return .toolResult(isError: (result["is_error"] as? Bool) ?? false)
      }
      return .other
    case "assistant":
      let blocks = message?["content"] as? [[String: Any]] ?? []
      guard let kind = blocks.last?["type"] as? String else { return .other }
      switch kind {
      case "tool_use": return .toolUse
      case "text": return .assistantText
      case "thinking": return .thinking
      default: return .other
      }
    default:
      return .other
    }
  }

  static func state(
    event: QoderTranscriptTailEvent?,
    age: TimeInterval,
    staleInterval: TimeInterval = 10 * 60,
    completedHoldInterval: TimeInterval = 10
  ) -> CodexActivityState {
    guard let event, age <= staleInterval else { return .idle }

    switch event {
    case .assistantText:
      return age <= completedHoldInterval ? .finished : .idle
    case .toolResult(isError: true):
      return .toolFailed
    case .userPrompt, .toolUse, .toolResult, .thinking, .other:
      return .running
    }
  }

  /// Reads the last non-empty line of a transcript without loading the whole
  /// file; sessions can grow to many megabytes.
  static func tailLine(of url: URL, maxBytes: Int = 256 * 1_024) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
    let readLength = min(UInt64(maxBytes), fileSize)
    try? handle.seek(toOffset: fileSize - readLength)
    guard let data = try? handle.read(upToCount: Int(readLength)) else { return nil }

    guard let text = String(data: data, encoding: .utf8) else {
      // A chunk boundary may split a multi-byte character; retry after the
      // first newline to realign with complete lines.
      guard
        let newline = data.firstIndex(of: UInt8(ascii: "\n")),
        let aligned = String(data: data[data.index(after: newline)...], encoding: .utf8)
      else { return nil }
      return lastNonEmptyLine(of: aligned)
    }
    return lastNonEmptyLine(of: text)
  }

  private static func lastNonEmptyLine(of text: String) -> String? {
    text
      .split(separator: "\n", omittingEmptySubsequences: true)
      .last
      .map(String.init)
  }
}
