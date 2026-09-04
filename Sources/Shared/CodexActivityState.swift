import Foundation

enum CodexActivityState: String, Codable, Equatable, Sendable {
  case idle
  case finished
  case running
  case awaitingAuthorization
  case toolFailed

  var title: String {
    switch self {
    case .idle: return "当前空闲"
    case .finished: return "任务结束"
    case .running: return "任务进行中"
    case .awaitingAuthorization: return "等待授权"
    case .toolFailed: return "工具执行失败"
    }
  }

  fileprivate var priority: Int {
    switch self {
    case .idle: return 0
    case .finished: return 1
    case .running: return 2
    case .awaitingAuthorization: return 3
    case .toolFailed: return 4
    }
  }
}

struct CodexActivityRecord: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let sessionID: String
  let turnID: String?
  let eventName: String
  let state: CodexActivityState
  let updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case sessionID = "sessionId"
    case turnID = "turnId"
    case eventName
    case state
    case updatedAt
  }
}

enum CodexActivityReducer {
  static func aggregate(
    _ records: [CodexActivityRecord],
    now: Date = Date(),
    staleInterval: TimeInterval = 12 * 60 * 60,
    completedHoldInterval: TimeInterval = 10
  ) -> CodexActivityState {
    records
      .filter { record in
        guard record.schemaVersion == 2 else { return false }
        let age = now.timeIntervalSince(record.updatedAt)
        if record.state == .finished {
          return age <= completedHoldInterval
        }
        return age <= staleInterval
      }
      .map(\.state)
      .max(by: { $0.priority < $1.priority })
      ?? .idle
  }
}
