import Foundation

enum GeminiTranscriptTailEvent: Equatable, Sendable {
  case userPrompt
  case toolRunning(name: String?)
  case awaitingUserInput
  case toolFailed(message: String?)
  case turnCompleted
  case other
}

enum GeminiActivityInterpreter {
  static func classify(line: String) -> (event: GeminiTranscriptTailEvent, date: Date?)? {
    guard
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
      let dictionary = object as? [String: Any]
    else { return nil }

    let createdAt = parseDate(dictionary["created_at"] as? String)
    let status = dictionary["status"] as? String
    let type = dictionary["type"] as? String

    if status == "ERROR" || type == "ERROR_MESSAGE" {
      let content = dictionary["content"] as? String
      return (.toolFailed(message: content), createdAt)
    }

    switch type {
    case "PLANNER_RESPONSE":
      let toolCalls = dictionary["tool_calls"] as? [[String: Any]] ?? []
      if toolCalls.contains(where: { ($0["name"] as? String) == "ask_question" }) {
        return (.awaitingUserInput, createdAt)
      } else if !toolCalls.isEmpty {
        let firstTool = toolCalls.first?["name"] as? String
        return (.toolRunning(name: firstTool), createdAt)
      } else {
        return (.turnCompleted, createdAt)
      }
    case "USER_INPUT":
      return (.userPrompt, createdAt)
    case "GENERIC":
      return (.other, createdAt)
    default:
      return (.other, createdAt)
    }
  }

  static func state(
    event: GeminiTranscriptTailEvent?,
    age: TimeInterval,
    staleInterval: TimeInterval = 12 * 60 * 60,
    completedHoldInterval: TimeInterval = 10
  ) -> CodexActivityState {
    guard let event, age <= staleInterval else { return .idle }

    switch event {
    case .awaitingUserInput:
      return .awaitingUserInput
    case .toolFailed:
      return .toolFailed
    case .turnCompleted:
      return age <= completedHoldInterval ? .finished : .idle
    case .userPrompt, .toolRunning, .other:
      return .running
    }
  }

  /// Reads the last non-empty line of a transcript without loading the entire file.
  static func tailLine(of url: URL, maxBytes: Int = 256 * 1024) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
    let readLength = min(UInt64(maxBytes), fileSize)
    try? handle.seek(toOffset: fileSize - readLength)
    guard let data = try? handle.read(upToCount: Int(readLength)) else { return nil }

    guard let text = String(data: data, encoding: .utf8) else {
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

  static func parseDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: string) { return date }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: string)
  }
}
