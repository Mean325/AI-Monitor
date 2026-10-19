import Foundation

protocol GeminiUsageFetching: Sendable {
  func fetch() async throws -> GeminiUsageSnapshot
}

enum GeminiClientError: LocalizedError {
  case brainDirectoryMissing
  case readFailed(String)

  var errorDescription: String? {
    switch self {
    case .brainDirectoryMissing:
      return "未找到 Gemini 会话目录（~/.gemini/antigravity/brain）。"
    case .readFailed(let message):
      return "读取 Gemini 用量失败：\(message)"
    }
  }
}

final class GeminiUsageClient: GeminiUsageFetching, @unchecked Sendable {
  private let brainURL: URL
  private let now: () -> Date

  init(brainURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
    if let brainURL {
      self.brainURL = brainURL
    } else if let override = ProcessInfo.processInfo.environment["GEMINI_BRAIN_DIR"],
      !override.isEmpty
    {
      self.brainURL = URL(fileURLWithPath: override)
    } else {
      self.brainURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini/antigravity/brain")
    }
    self.now = now
  }

  func fetch() async throws -> GeminiUsageSnapshot {
    let brainURL = self.brainURL
    let now = self.now()
    return try await Task.detached(priority: .utility) {
      try Self.aggregate(brainURL: brainURL, now: now)
    }.value
  }

  func fetchSynchronously(now: Date = Date()) throws -> GeminiUsageSnapshot {
    try Self.aggregate(brainURL: brainURL, now: now)
  }

  static func aggregate(brainURL: URL, now: Date) throws -> GeminiUsageSnapshot {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    let weekStart = now.addingTimeInterval(-7 * 24 * 60 * 60)

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: brainURL.path) else {
      return GeminiUsageSnapshot(
        todayTokens: 0, weekTokens: 0, todaySessions: 0, model: nil, lastActiveDate: nil)
    }

    let sessionDirs =
      (try? fileManager.contentsOfDirectory(
        at: brainURL,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    var todayTokens = 0
    var weekTokens = 0
    var todaySessions = Set<String>()
    var model: String?
    var modelDate: Date?
    var lastActive: Date?

    for dir in sessionDirs {
      let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDir else { continue }
      let sessionID = dir.lastPathComponent

      let transcriptCandidates = [
        dir.appendingPathComponent(".system_generated/logs/transcript.jsonl"),
        dir.appendingPathComponent("transcript.jsonl"),
      ]

      guard let transcriptURL = transcriptCandidates.first(where: { fileManager.fileExists(atPath: $0.path) })
      else { continue }

      if let modified = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate,
        modified < weekStart
      {
        continue
      }

      guard let contents = try? String(contentsOf: transcriptURL, encoding: .utf8) else { continue }

      for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
        guard
          let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
          let dictionary = object as? [String: Any]
        else { continue }

        let createdAt = GeminiActivityInterpreter.parseDate(dictionary["created_at"] as? String)
        let lineModel = dictionary["modelName"] as? String ?? dictionary["model"] as? String

        if let createdAt {
          if createdAt > (lastActive ?? .distantPast) {
            lastActive = createdAt
          }
          if let lineModel, !lineModel.isEmpty, createdAt > (modelDate ?? .distantPast) {
            model = lineModel
            modelDate = createdAt
          }
        }

        guard (dictionary["type"] as? String) == "PLANNER_RESPONSE" else { continue }

        let inputTokens = dictionary["input_tokens"] as? Int ?? 0
        let cacheReadTokens = dictionary["cache_read_tokens"] as? Int ?? 0
        let outputTokens = dictionary["output_tokens"] as? Int ?? 0
        let totalTurnTokens = inputTokens + cacheReadTokens + outputTokens

        if let createdAt {
          if createdAt >= weekStart {
            weekTokens += totalTurnTokens
          }
          if createdAt >= todayStart {
            todayTokens += totalTurnTokens
            todaySessions.insert(sessionID)
          }
        }
      }
    }

    return GeminiUsageSnapshot(
      todayTokens: todayTokens,
      weekTokens: weekTokens,
      todaySessions: todaySessions.count,
      model: model,
      lastActiveDate: lastActive
    )
  }
}
