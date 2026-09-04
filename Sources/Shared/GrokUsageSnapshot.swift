import Foundation

enum GrokUsagePeriodType: String, Equatable, Sendable {
  case daily
  case weekly
  case monthly
  case unknown
}

struct GrokUsageSnapshot: Equatable, Sendable {
  let remainingPercent: Int
  let usedPercent: Double
  let periodType: GrokUsagePeriodType
  let periodStart: Date?
  let periodEnd: Date?
  let subscriptionTier: String?
  let prepaidBalance: Int
  let onDemandUsed: Int
  let onDemandCap: Int

  var remainingProgress: Double {
    Double(max(0, min(100, remainingPercent))) / 100
  }

  var windowTitle: String {
    switch periodType {
    case .daily: return "本日剩余"
    case .weekly: return "本周剩余"
    case .monthly: return "本月剩余"
    case .unknown: return "周期剩余"
    }
  }

  var windowDescription: String {
    switch periodType {
    case .daily: return "1 天周期"
    case .weekly: return "7 天周期"
    case .monthly: return "30 天周期"
    case .unknown: return "当前周期"
    }
  }

  var planDisplayName: String {
    guard let subscriptionTier, !subscriptionTier.isEmpty else { return "未知套餐" }
    let spaced = subscriptionTier.replacingOccurrences(
      of: "([a-z])([A-Z])",
      with: "$1 $2",
      options: .regularExpression
    )
    if spaced.lowercased() == "grokpro" || spaced == "Grok Pro" {
      return "Grok Pro"
    }
    return spaced
  }

  var compactPlanName: String {
    let name = planDisplayName
    if name.lowercased().hasPrefix("grok ") {
      return String(name.dropFirst(5))
    }
    return name
  }

  var hasData: Bool {
    remainingPercent >= 0
  }

  static let sample = GrokUsageSnapshot(
    remainingPercent: 92,
    usedPercent: 8,
    periodType: .weekly,
    periodStart: Calendar.current.date(
      from: DateComponents(year: 2026, month: 8, day: 31, hour: 13, minute: 42)),
    periodEnd: Calendar.current.date(
      from: DateComponents(year: 2026, month: 9, day: 7, hour: 13, minute: 42)),
    subscriptionTier: "GrokPro",
    prepaidBalance: 0,
    onDemandUsed: 0,
    onDemandCap: 0
  )
}
