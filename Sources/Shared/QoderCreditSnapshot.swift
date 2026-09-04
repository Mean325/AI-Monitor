import Foundation

/// Credit 额度与 context token 数据，从 Qoder 运行日志中提取。
struct QoderCreditSnapshot: Equatable, Sendable {
  // MARK: - Credit 额度
  let userType: String?
  let creditsUsed: Int
  let creditsTotal: Int
  let creditsRemaining: Int
  let usagePercentage: Double
  let isQuotaExceeded: Bool

  // MARK: - Context Token（当前会话）
  let contextUsedTokens: Int
  let contextLimitTokens: Int

  var creditsPercentageDisplay: String {
    String(format: "%.0f%%", usagePercentage * 100)
  }

  var contextPercentageDisplay: String {
    guard contextLimitTokens > 0 else { return "0%" }
    return String(format: "%.0f%%", Double(contextUsedTokens) / Double(contextLimitTokens) * 100)
  }

  var hasData: Bool {
    creditsTotal > 0 || contextLimitTokens > 0
  }

  static let sample = QoderCreditSnapshot(
    userType: "personal_professional_trial",
    creditsUsed: 30,
    creditsTotal: 300,
    creditsRemaining: 270,
    usagePercentage: 0.1,
    isQuotaExceeded: false,
    contextUsedTokens: 140_775,
    contextLimitTokens: 200_000
  )
}
