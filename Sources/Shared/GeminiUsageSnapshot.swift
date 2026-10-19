import Foundation

struct GeminiUsageSnapshot: Equatable, Sendable {
  let todayTokens: Int
  let weekTokens: Int
  let todaySessions: Int
  let model: String?
  let lastActiveDate: Date?

  var modelDisplayName: String? {
    guard let model, !model.isEmpty else { return nil }
    if let range = model.range(of: "gemini-") {
      let suffix = model[range.upperBound...]
      if !suffix.isEmpty { return String(suffix) }
    }
    return model
  }

  var hasData: Bool {
    todayTokens > 0 || weekTokens > 0 || todaySessions > 0 || lastActiveDate != nil
  }

  static let sample = GeminiUsageSnapshot(
    todayTokens: 215_400,
    weekTokens: 1_480_000,
    todaySessions: 8,
    model: "gemini-3.8-flash",
    lastActiveDate: Calendar.current.date(
      from: DateComponents(year: 2026, month: 10, day: 19, hour: 11, minute: 30))
  )
}
