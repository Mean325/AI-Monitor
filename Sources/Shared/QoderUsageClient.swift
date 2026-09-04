import Foundation

protocol QoderUsageFetching: Sendable {
  func fetch() async throws -> QoderUsageSnapshot
}

enum QoderClientError: LocalizedError {
  case projectsDirectoryMissing
  case readFailed(String)

  var errorDescription: String? {
    switch self {
    case .projectsDirectoryMissing:
      return "未找到 Qoder 会话目录（~/.qoder/projects）。"
    case .readFailed(let message):
      return "读取 Qoder 用量失败：\(message)"
    }
  }
}

final class QoderUsageClient: QoderUsageFetching, @unchecked Sendable {
  private let projectsURL: URL
  private let now: () -> Date

  init(projectsURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
    if let projectsURL {
      self.projectsURL = projectsURL
    } else if let override = ProcessInfo.processInfo.environment["QODER_PROJECTS_DIR"],
      !override.isEmpty
    {
      self.projectsURL = URL(fileURLWithPath: override)
    } else {
      self.projectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".qoder/projects")
    }
    self.now = now
  }

  func fetch() async throws -> QoderUsageSnapshot {
    let projectsURL = self.projectsURL
    let now = self.now()
    return try await Task.detached(priority: .utility) {
      try Self.aggregate(projectsURL: projectsURL, now: now)
    }.value
  }

  func fetchSynchronously(now: Date = Date()) throws -> QoderUsageSnapshot {
    try Self.aggregate(projectsURL: projectsURL, now: now)
  }

  static func aggregate(projectsURL: URL, now: Date) throws -> QoderUsageSnapshot {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    let weekStart = now.addingTimeInterval(-7 * 24 * 60 * 60)

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: projectsURL.path) else {
      return QoderUsageSnapshot(
        todayPrompts: 0, weekPrompts: 0, todaySessions: 0, todayToolCalls: 0, lastActiveDate: nil)
    }

    let projectDirs =
      (try? fileManager.contentsOfDirectory(
        at: projectsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    var todayPrompts = 0
    var weekPrompts = 0
    var todaySessions = Set<String>()
    var todayToolCalls = 0
    var lastActive: Date?

    for dir in projectDirs {
      let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDir else { continue }

      let transcriptDir = dir.appendingPathComponent("transcript", isDirectory: true)
      let files =
        (try? fileManager.contentsOfDirectory(
          at: transcriptDir,
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

          let type = dictionary["type"] as? String
          guard type == "user" || type == "assistant" else { continue }

          let timestamp = parseDate(dictionary["timestamp"] as? String)
          let sessionId = dictionary["sessionId"] as? String
          let message = dictionary["message"] as? [String: Any]

          guard let timestamp else { continue }

          if timestamp > (lastActive ?? .distantPast) {
            lastActive = timestamp
          }

          if type == "user" {
            // Real prompts carry a plain string; tool results arrive as arrays.
            guard message?["content"] is String else { continue }
            if timestamp >= weekStart {
              weekPrompts += 1
            }
            if timestamp >= todayStart {
              todayPrompts += 1
              if let sessionId { todaySessions.insert(sessionId) }
            }
          } else if timestamp >= todayStart {
            let blocks = message?["content"] as? [[String: Any]] ?? []
            todayToolCalls += blocks.filter { ($0["type"] as? String) == "tool_use" }.count
          }
        }
      }
    }

    return QoderUsageSnapshot(
      todayPrompts: todayPrompts,
      weekPrompts: weekPrompts,
      todaySessions: todaySessions.count,
      todayToolCalls: todayToolCalls,
      lastActiveDate: lastActive
    )
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
    if let date = fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) {
      return date
    }
    // Qoder writes microsecond fractions; ISO8601DateFormatter only accepts
    // milliseconds, so truncate the fraction to three digits and retry.
    guard let dotIndex = string.firstIndex(of: ".") else { return nil }
    let fractionStart = string.index(after: dotIndex)
    guard
      let fractionEnd = string[fractionStart...].firstIndex(where: { !$0.isNumber }),
      fractionEnd > fractionStart
    else { return nil }
    let fraction = String(string[fractionStart..<fractionEnd].prefix(3))
    let normalized =
      String(string[..<fractionStart])
      + fraction.padding(toLength: 3, withPad: "0", startingAt: 0)
      + String(string[fractionEnd...])
    return fractionalFormatter.date(from: normalized)
  }
}
