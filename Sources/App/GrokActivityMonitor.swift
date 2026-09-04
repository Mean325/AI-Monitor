import Darwin
import Foundation

/// Watches `~/.grok/active_sessions.json` and treats a live Grok CLI process
/// as an in-progress task. There is no extra hook to install.
@MainActor
final class GrokActivityMonitor: CodexActivityMonitoring {
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private let activeSessionsURL: URL
  private let fileManager: FileManager
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false

  init(
    activeSessionsURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    if let activeSessionsURL {
      self.activeSessionsURL = activeSessionsURL
    } else if let override = ProcessInfo.processInfo.environment["GROK_ACTIVE_SESSIONS_PATH"],
      !override.isEmpty
    {
      self.activeSessionsURL = URL(fileURLWithPath: override)
    } else {
      self.activeSessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/active_sessions.json")
    }
    self.fileManager = fileManager
  }

  deinit {
    pollingTask?.cancel()
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    refresh()
    startPolling()
  }

  func stop() {
    isStarted = false
    pollingTask?.cancel()
    pollingTask = nil
  }

  var authDirectoryExists: Bool {
    fileManager.fileExists(
      atPath: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/auth.json").path
    )
  }

  func refresh() {
    guard let data = try? Data(contentsOf: activeSessionsURL),
      let sessions = try? JSONDecoder().decode([GrokActiveSession].self, from: data)
    else {
      updateState(.idle)
      return
    }

    let live = sessions.filter { isProcessRunning($0.pid) }
    if live.isEmpty {
      updateState(.idle)
      return
    }

    let newest = live.compactMap(\.openedAtDate).max() ?? Date()
    updateLastEventDate(newest)
    updateState(.running)
  }

  private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
          return
        }
        guard let self, self.isStarted else { return }
        self.refresh()
      }
    }
  }

  private func isProcessRunning(_ pid: Int) -> Bool {
    guard pid > 0 else { return false }
    return kill(pid_t(pid), 0) == 0
  }

  private func updateState(_ newState: CodexActivityState) {
    guard state != newState else { return }
    state = newState
    onStateChange?(newState)
  }

  private func updateLastEventDate(_ newDate: Date?) {
    guard let newDate, lastEventDate != newDate else { return }
    lastEventDate = newDate
    onEventObserved?(newDate)
  }
}

private struct GrokActiveSession: Decodable {
  let sessionId: String?
  let pid: Int
  let openedAt: String?

  var openedAtDate: Date? {
    GrokActiveSession.parseDate(openedAt)
  }

  private enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case pid
    case openedAt = "opened_at"
  }

  private static func parseDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    if let date = fractional.date(from: string) ?? plain.date(from: string) {
      return date
    }
    return nil
  }
}

private let fractional: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

private let plain: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()
