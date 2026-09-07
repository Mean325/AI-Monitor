import Darwin
import Foundation

/// Watches live Grok CLI sessions and derives task state from `events.jsonl`.
/// A running `grok` process only means the TUI is open.
@MainActor
final class GrokActivityMonitor: CodexActivityMonitoring {
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private let activeSessionsURL: URL
  private let sessionsDirectoryURL: URL
  private let completedHoldInterval: TimeInterval
  private let fileManager: FileManager
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false

  init(
    activeSessionsURL: URL? = nil,
    sessionsDirectoryURL: URL? = nil,
    completedHoldInterval: TimeInterval = 10,
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
    if let sessionsDirectoryURL {
      self.sessionsDirectoryURL = sessionsDirectoryURL
    } else if let override = ProcessInfo.processInfo.environment["GROK_SESSIONS_DIR"],
      !override.isEmpty
    {
      self.sessionsDirectoryURL = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      self.sessionsDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/sessions", isDirectory: true)
    }
    self.completedHoldInterval = completedHoldInterval
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

    var states: [CodexActivityState] = []
    var newestEventDate: Date?
    for session in live {
      let event = eventsURL(for: session).flatMap { GrokActivityInterpreter.latestEvent(in: $0) }
      states.append(
        GrokActivityInterpreter.state(
          event: event,
          processLive: true,
          completedHoldInterval: completedHoldInterval
        )
      )
      if let date = event?.date ?? session.openedAtDate,
        date > (newestEventDate ?? .distantPast)
      {
        newestEventDate = date
      }
    }

    if let newestEventDate {
      updateLastEventDate(newestEventDate)
    }
    updateState(GrokActivityInterpreter.aggregate(states))
  }

  private func eventsURL(for session: GrokActiveSession) -> URL? {
    if let sessionID = session.sessionId, !sessionID.isEmpty, let cwd = session.cwd, !cwd.isEmpty {
      let encoded = cwd.addingPercentEncoding(withAllowedCharacters: grokPathAllowed) ?? cwd
      let url = sessionsDirectoryURL
        .appendingPathComponent(encoded, isDirectory: true)
        .appendingPathComponent(sessionID, isDirectory: true)
        .appendingPathComponent("events.jsonl")
      if fileManager.fileExists(atPath: url.path) {
        return url
      }
    }

    guard let sessionID = session.sessionId, !sessionID.isEmpty,
      let enumerator = fileManager.enumerator(
        at: sessionsDirectoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return nil }

    for case let url as URL in enumerator where url.lastPathComponent == "events.jsonl" {
      if url.deletingLastPathComponent().lastPathComponent == sessionID {
        return url
      }
    }
    return nil
  }

  private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 500_000_000)
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

private let grokPathAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

private struct GrokActiveSession: Decodable {
  let sessionId: String?
  let pid: Int
  let cwd: String?
  let openedAt: String?

  var openedAtDate: Date? {
    GrokActiveSession.parseDate(openedAt)
  }

  private enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case pid
    case cwd
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
