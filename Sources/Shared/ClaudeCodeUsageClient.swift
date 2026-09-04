import Foundation

protocol ClaudeCodeUsageFetching: Sendable {
  func fetch() async throws -> ClaudeCodeUsageSnapshot
}

enum ClaudeCodeClientError: LocalizedError {
  case projectsDirectoryMissing
  case readFailed(String)

  var errorDescription: String? {
    switch self {
    case .projectsDirectoryMissing:
      return "未找到 Claude Code 会话目录（~/.claude/projects）。"
    case .readFailed(let message):
      return "读取 Claude Code 用量失败：\(message)"
    }
  }
}

final class ClaudeCodeUsageClient: ClaudeCodeUsageFetching, @unchecked Sendable {
  private let projectsURL: URL
  private let now: () -> Date

  init(projectsURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
    if let projectsURL {
      self.projectsURL = projectsURL
    } else if let override = ProcessInfo.processInfo.environment["CLAUDE_PROJECTS_DIR"],
      !override.isEmpty
    {
      self.projectsURL = URL(fileURLWithPath: override)
    } else {
      self.projectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    }
    self.now = now
  }

  func fetch() async throws -> ClaudeCodeUsageSnapshot {
    let projectsURL = self.projectsURL
    let now = self.now()
    return try await Task.detached(priority: .utility) {
      try Self.aggregate(projectsURL: projectsURL, now: now)
    }.value
  }

  func fetchSynchronously(now: Date = Date()) throws -> ClaudeCodeUsageSnapshot {
    try Self.aggregate(projectsURL: projectsURL, now: now)
  }

  static func aggregate(projectsURL: URL, now: Date) throws -> ClaudeCodeUsageSnapshot {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    let weekStart = now.addingTimeInterval(-7 * 24 * 60 * 60)

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: projectsURL.path) else {
      return ClaudeCodeUsageSnapshot(
        todayTokens: 0, weekTokens: 0, todaySessions: 0, model: nil, lastActiveDate: nil)
    }

    let projectDirs =
      (try? fileManager.contentsOfDirectory(
        at: projectsURL,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    var todayTokens = 0
    var weekTokens = 0
    var todaySessions = Set<String>()
    var model: String?
    var modelDate: Date?
    var lastActive: Date?

    for dir in projectDirs {
      let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDir else { continue }

      let files =
        (try? fileManager.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: [.skipsHiddenFiles]
        )) ?? []

      for file in files where file.pathExtension == "jsonl" {
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate,
          modified < weekStart
        {
          continue
        }

        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
          guard
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let dictionary = object as? [String: Any]
          else { continue }
          guard (dictionary["type"] as? String) == "assistant" else { continue }

          let message = dictionary["message"] as? [String: Any]
          let usage = message?["usage"] as? [String: Any]
          let lineModel = message?["model"] as? String
          let timestamp = parseDate(dictionary["timestamp"] as? String)
          let sessionId = dictionary["sessionId"] as? String

          let tokens = totalTokens(usage)

          if let timestamp {
            if timestamp >= weekStart {
              weekTokens += tokens
            }
            if timestamp >= todayStart {
              todayTokens += tokens
              if let sessionId { todaySessions.insert(sessionId) }
            }
            if timestamp > (lastActive ?? .distantPast) {
              lastActive = timestamp
            }
            if let lineModel, timestamp > (modelDate ?? .distantPast) {
              model = lineModel
              modelDate = timestamp
            }
          }
        }
      }
    }

    return ClaudeCodeUsageSnapshot(
      todayTokens: todayTokens,
      weekTokens: weekTokens,
      todaySessions: todaySessions.count,
      model: model,
      lastActiveDate: lastActive
    )
  }

  private static func totalTokens(_ usage: [String: Any]?) -> Int {
    // Headline usage = fresh input + generated output. Cache reads are reused
    // context (billed cheaply) and would otherwise dominate the number, so they
    // are excluded from the glanceable total.
    guard let usage else { return 0 }
    return intValue(usage["input_tokens"]) + intValue(usage["output_tokens"])
  }

  private static func intValue(_ any: Any?) -> Int {
    if let number = any as? NSNumber { return number.intValue }
    return any as? Int ?? 0
  }

  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let plainFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static func parseDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
  }
}
