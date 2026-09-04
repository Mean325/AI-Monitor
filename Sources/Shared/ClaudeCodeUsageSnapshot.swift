import Foundation

struct ClaudeCodeUsageSnapshot: Equatable, Sendable {
  let todayTokens: Int
  let weekTokens: Int
  let todaySessions: Int
  let model: String?
  let lastActiveDate: Date?

  var modelDisplayName: String? {
    guard let model, !model.isEmpty else { return nil }
    if let range = model.range(of: "claude-") {
      let suffix = model[range.upperBound...]
      if !suffix.isEmpty { return String(suffix) }
    }
    return model
  }

  var hasData: Bool {
    todayTokens > 0 || weekTokens > 0 || todaySessions > 0 || lastActiveDate != nil
  }

  static let sample = ClaudeCodeUsageSnapshot(
    todayTokens: 184_320,
    weekTokens: 1_264_500,
    todaySessions: 6,
    model: "claude-opus-4-8",
    lastActiveDate: Calendar.current.date(
      from: DateComponents(year: 2026, month: 7, day: 28, hour: 14, minute: 8))
  )
}

enum ClaudeCodeTokenFormatter {
  static func string(from tokens: Int) -> String {
    if tokens < 1_000 { return "\(tokens)" }
    if tokens < 1_000_000 {
      return String(format: "%.1fk", Double(tokens) / 1_000)
    }
    return String(format: "%.1fM", Double(tokens) / 1_000_000)
  }
}
