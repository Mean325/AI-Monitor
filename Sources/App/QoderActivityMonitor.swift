import Foundation

/// Watches `~/.qoder/projects/*/transcript/*.jsonl` and infers the current
/// task state from the newest transcript entry. Unlike Codex and Claude Code
/// there is no hook to install: Qoder keeps its own session log up to date.
@MainActor
final class QoderActivityMonitor: CodexActivityMonitoring {
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private let projectsURL: URL
  private let staleInterval: TimeInterval
  private let completedHoldInterval: TimeInterval
  private let fileManager: FileManager
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false

  init(
    projectsURL: URL? = nil,
    staleInterval: TimeInterval = 10 * 60,
    completedHoldInterval: TimeInterval = 10,
    fileManager: FileManager = .default
  ) {
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
    self.staleInterval = staleInterval
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

  var projectsDirectoryExists: Bool {
    fileManager.fileExists(atPath: projectsURL.path)
  }

  func refresh() {
    guard let latest = latestTranscript() else {
      updateState(.idle)
      return
    }

    updateLastEventDate(latest.modified)

    let age = Date().timeIntervalSince(latest.modified)
    let event = QoderActivityInterpreter.tailLine(of: latest.url)
      .flatMap(QoderActivityInterpreter.classify(line:))
    updateState(
      QoderActivityInterpreter.state(
        event: event,
        age: age,
        staleInterval: staleInterval,
        completedHoldInterval: completedHoldInterval
      )
    )
  }

  private func latestTranscript() -> (url: URL, modified: Date)? {
    let projectDirs =
      (try? fileManager.contentsOfDirectory(
        at: projectsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    var newest: (url: URL, modified: Date)?
    for dir in projectDirs {
      let transcriptDir = dir.appendingPathComponent("transcript", isDirectory: true)
      let files =
        (try? fileManager.contentsOfDirectory(
          at: transcriptDir,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: [.skipsHiddenFiles]
        )) ?? []

      for file in files where file.pathExtension == "jsonl" {
        guard
          let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        else { continue }
        if modified > (newest?.modified ?? .distantPast) {
          newest = (file, modified)
        }
      }
    }
    return newest
  }

  private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        guard let self, self.isStarted else { return }
        self.refresh()
      }
    }
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
