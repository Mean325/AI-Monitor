import Foundation

struct QoderUsageSnapshot: Equatable, Sendable {
  let todayPrompts: Int
  let weekPrompts: Int
  let todaySessions: Int
  let todayToolCalls: Int
  let lastActiveDate: Date?

  var hasData: Bool {
    todayPrompts > 0 || weekPrompts > 0 || todaySessions > 0 || todayToolCalls > 0
      || lastActiveDate != nil
  }

  static let sample = QoderUsageSnapshot(
    todayPrompts: 26,
    weekPrompts: 142,
    todaySessions: 5,
    todayToolCalls: 87,
    lastActiveDate: Calendar.current.date(
      from: DateComponents(year: 2026, month: 7, day: 28, hour: 15, minute: 26))
  )
}
