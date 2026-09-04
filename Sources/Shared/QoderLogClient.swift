import Foundation

protocol QoderCreditFetching: Sendable {
  func fetch() async throws -> QoderCreditSnapshot
}

enum QoderLogClientError: LocalizedError {
  case logsDirectoryMissing
  case noRecentLogs
  case parseFailed

  var errorDescription: String? {
    switch self {
    case .logsDirectoryMissing:
      return "未找到 Qoder 日志目录。"
    case .noRecentLogs:
      return "Qoder 日志为空，请确保 Qoder 正在运行。"
    case .parseFailed:
      return "解析 Qoder 日志失败。"
    }
  }
}

/// 从 Qoder 运行日志中提取 credit 额度和 context token 数据。
///
/// 日志路径：`~/Library/Application Support/Qoder/logs/<timestamp>/questWindow/`
/// - `renderer.log` 包含 credit 额度摘要
/// - `agent.log` 包含 context token 用量
final class QoderLogClient: QoderCreditFetching, @unchecked Sendable {
  private let logsURL: URL
  private let fileManager: FileManager

  init(
    logsURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    if let logsURL {
      self.logsURL = logsURL
    } else if let override = ProcessInfo.processInfo.environment["QODER_LOGS_DIR"],
      !override.isEmpty
    {
      self.logsURL = URL(fileURLWithPath: override)
    } else {
      self.logsURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Qoder/logs")
    }
    self.fileManager = fileManager
  }

  func fetch() async throws -> QoderCreditSnapshot {
    let logsURL = self.logsURL
    let fileManager = self.fileManager
    return try await Task.detached(priority: .utility) {
      try Self.parse(logsURL: logsURL, fileManager: fileManager)
    }.value
  }

  func fetchSynchronously() throws -> QoderCreditSnapshot {
    try Self.parse(logsURL: logsURL, fileManager: fileManager)
  }

  // MARK: - 解析逻辑

  static func parse(logsURL: URL, fileManager: FileManager = .default) throws -> QoderCreditSnapshot {
    guard fileManager.fileExists(atPath: logsURL.path) else {
      return .empty
    }

    // 找到最新的日志目录
    guard let latestLogDir = findLatestLogDirectory(logsURL, fileManager: fileManager) else {
      return .empty
    }

    let questWindowDir = latestLogDir.appendingPathComponent("questWindow", isDirectory: true)

    // 解析 renderer.log 获取 credit 数据
    let rendererLog = questWindowDir.appendingPathComponent("renderer.log")
    let creditSnapshot = parseCreditSummary(from: rendererLog, fileManager: fileManager)

    // 解析 agent.log 获取 context token 数据
    let agentLog = questWindowDir.appendingPathComponent("agent.log")
    let contextTokens = parseContextUsage(from: agentLog, fileManager: fileManager)

    return QoderCreditSnapshot(
      userType: creditSnapshot.userType,
      creditsUsed: creditSnapshot.creditsUsed,
      creditsTotal: creditSnapshot.creditsTotal,
      creditsRemaining: creditSnapshot.creditsRemaining,
      usagePercentage: creditSnapshot.usagePercentage,
      isQuotaExceeded: creditSnapshot.isQuotaExceeded,
      contextUsedTokens: contextTokens.used,
      contextLimitTokens: contextTokens.limit
    )
  }

  // MARK: - 查找最新日志目录

  private static func findLatestLogDirectory(_ logsURL: URL, fileManager: FileManager) -> URL? {
    let directories = (try? fileManager.contentsOfDirectory(
      at: logsURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    return directories
      .filter { url in
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
      }
      .max(by: { lhs, rhs in
        let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return lhsDate < rhsDate
      })
  }

  // MARK: - 解析 Credit 摘要

  private static func parseCreditSummary(from url: URL, fileManager: FileManager) -> (
    userType: String?, creditsUsed: Int, creditsTotal: Int, creditsRemaining: Int,
    usagePercentage: Double, isQuotaExceeded: Bool
  ) {
    var result = (userType: nil as String?, creditsUsed: 0, creditsTotal: 0, creditsRemaining: 0, usagePercentage: 0.0, isQuotaExceeded: false)

    guard let content = readLastLines(of: url, lineCount: 500, fileManager: fileManager) else {
      return result
    }

    // 查找最后一条 Credit usage summary
    // 格式: Credit usage summary: userType=personal_professional_trial, totalUsagePercentage=0.1, isQuotaExceeded=false, userQuota=used=30, total=300, remaining=270, percentage=0.1, unit=credits
    for line in content.components(separatedBy: .newlines).reversed() {
      guard line.contains("Credit usage summary:") else { continue }

      // 提取 userType
      if let range = line.range(of: "userType=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          result.userType = String(line[start..<endRange.lowerBound])
        }
      }

      // 提取 totalUsagePercentage
      if let range = line.range(of: "totalUsagePercentage=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          let value = String(line[start..<endRange.lowerBound])
          result.usagePercentage = Double(value) ?? 0
        }
      }

      // 提取 isQuotaExceeded
      if let range = line.range(of: "isQuotaExceeded=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          let value = String(line[start..<endRange.lowerBound])
          result.isQuotaExceeded = value == "true"
        }
      }

      // 提取 userQuota=used=X
      if let range = line.range(of: "userQuota=used=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          let value = String(line[start..<endRange.lowerBound])
          result.creditsUsed = Int(value) ?? 0
        }
      }

      // 提取 total=X
      if let range = line.range(of: "total=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          let value = String(line[start..<endRange.lowerBound])
          result.creditsTotal = Int(value) ?? 0
        }
      }

      // 提取 remaining=X
      if let range = line.range(of: "remaining=") {
        let start = range.upperBound
        if let endRange = line[start...].range(of: ",") {
          let value = String(line[start..<endRange.lowerBound])
          result.creditsRemaining = Int(value) ?? 0
        }
      }

      break  // 只取最后一条
    }

    return result
  }

  // MARK: - 解析 Context Token

  private static func parseContextUsage(from url: URL, fileManager: FileManager) -> (used: Int, limit: Int) {
    var result = (used: 0, limit: 0)

    guard let content = readLastLines(of: url, lineCount: 200, fileManager: fileManager) else {
      return result
    }

    // 查找最后一条 Context usage update
    // 格式: Context usage update: {"sessionId":"...","requestId":"...","usedTokens":140775,"limitTokens":200000}
    for line in content.components(separatedBy: .newlines).reversed() {
      guard line.contains("Context usage update:") else { continue }

      // 提取 JSON 部分
      guard let jsonStart = line.range(of: "{") else { continue }
      let jsonString = String(line[jsonStart.lowerBound...])

      guard let jsonData = jsonString.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
      else { continue }

      if let used = json["usedTokens"] as? Int {
        result.used = used
      }
      if let limit = json["limitTokens"] as? Int {
        result.limit = limit
      }

      break  // 只取最后一条
    }

    return result
  }

  // MARK: - 读取文件末尾

  private static func readLastLines(of url: URL, lineCount: Int, fileManager: FileManager) -> String? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    // 读取最后 64KB
    guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
    let readLength = min(UInt64(64 * 1024), fileSize)
    try? handle.seek(toOffset: fileSize - readLength)
    guard let data = try? handle.read(upToCount: Int(readLength)) else { return nil }

    return String(data: data, encoding: .utf8)
  }
}

extension QoderCreditSnapshot {
  static let empty = QoderCreditSnapshot(
    userType: nil,
    creditsUsed: 0,
    creditsTotal: 0,
    creditsRemaining: 0,
    usagePercentage: 0,
    isQuotaExceeded: false,
    contextUsedTokens: 0,
    contextLimitTokens: 0
  )
}
