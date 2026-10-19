import Darwin
import Foundation

private let defaultGeminiActivityDirectoryURL = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("CodexLinxDisplay/gemini-activity", isDirectory: true)

private let defaultGeminiBrainDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)

@MainActor
final class GeminiActivityMonitor: CodexActivityMonitoring {
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private let directoryURL: URL
  private let brainURL: URL
  private let staleInterval: TimeInterval
  private let completedHoldInterval: TimeInterval
  private let fileManager: FileManager
  private var directorySource: DispatchSourceFileSystemObject?
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false

  init(
    directoryURL: URL = defaultGeminiActivityDirectoryURL,
    brainURL: URL = defaultGeminiBrainDirectoryURL,
    staleInterval: TimeInterval = 12 * 60 * 60,
    completedHoldInterval: TimeInterval = 10,
    fileManager: FileManager = .default
  ) {
    if let override = ProcessInfo.processInfo.environment["GEMINI_ACTIVITY_DIR"],
      !override.isEmpty
    {
      self.directoryURL = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      self.directoryURL = directoryURL
    }
    if let override = ProcessInfo.processInfo.environment["GEMINI_BRAIN_DIR"],
      !override.isEmpty
    {
      self.brainURL = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      self.brainURL = brainURL
    }
    self.staleInterval = staleInterval
    self.completedHoldInterval = completedHoldInterval
    self.fileManager = fileManager
  }

  deinit {
    directorySource?.cancel()
    pollingTask?.cancel()
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true

    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
    } catch {}

    refresh()
    startDirectorySource()
    startPolling()
  }

  func stop() {
    isStarted = false
    directorySource?.cancel()
    directorySource = nil
    pollingTask?.cancel()
    pollingTask = nil
  }

  func refresh() {
    let now = Date()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    // 1. Read hook-based activity records
    let hookRecords =
      (try? fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ))?
      .filter { $0.pathExtension == "json" }
      .compactMap { url -> CodexActivityRecord? in
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let record = try? decoder.decode(CodexActivityRecord.self, from: data) else {
          return nil
        }
        guard record.source == "gemini" else { return nil }
        return record
      }
      ?? []

    // 2. Read fallback session/transcript activity records
    let sessionRecords = readSessionRecords(now: now)

    // 3. Reconcile records: Hook records take priority for the same session ID
    let records = reconciledRecords(hookRecords: hookRecords, sessionRecords: sessionRecords)

    let newestDate = records.map(\.updatedAt).max()
    if let newestDate {
      updateLastEventDate(newestDate)
    }

    let nextState = CodexActivityReducer.aggregate(
      records,
      now: now,
      staleInterval: staleInterval,
      completedHoldInterval: completedHoldInterval
    )
    updateState(nextState)
  }

  private func readSessionRecords(now: Date) -> [CodexActivityRecord] {
    guard fileManager.fileExists(atPath: brainURL.path) else { return [] }

    let sessionDirs =
      (try? fileManager.contentsOfDirectory(
        at: brainURL,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    var records: [CodexActivityRecord] = []

    for dir in sessionDirs {
      let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDir else { continue }
      let sessionID = dir.lastPathComponent

      let transcriptCandidates = [
        dir.appendingPathComponent(".system_generated/logs/transcript.jsonl"),
        dir.appendingPathComponent("transcript.jsonl"),
      ]

      guard let transcriptURL = transcriptCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
            let modified = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            now.timeIntervalSince(modified) <= staleInterval
      else { continue }

      guard let tailLine = GeminiActivityInterpreter.tailLine(of: transcriptURL),
            let classified = GeminiActivityInterpreter.classify(line: tailLine)
      else { continue }

      let eventDate = classified.date ?? modified
      let age = now.timeIntervalSince(eventDate)
      let derivedState = GeminiActivityInterpreter.state(
        event: classified.event,
        age: age,
        staleInterval: staleInterval,
        completedHoldInterval: completedHoldInterval
      )

      records.append(
        CodexActivityRecord(
          schemaVersion: 2,
          sessionID: sessionID,
          turnID: nil,
          eventName: "transcript",
          state: derivedState,
          updatedAt: eventDate,
          source: "gemini"
        )
      )
    }

    return records
  }

  private func reconciledRecords(
    hookRecords: [CodexActivityRecord],
    sessionRecords: [CodexActivityRecord]
  ) -> [CodexActivityRecord] {
    if hookRecords.isEmpty { return sessionRecords }

    var result: [CodexActivityRecord] = []
    let hookSessions = Set(hookRecords.map(\.sessionID))

    result.append(contentsOf: hookRecords)
    for sessionRecord in sessionRecords {
      if !hookSessions.contains(sessionRecord.sessionID) {
        result.append(sessionRecord)
      }
    }
    return result
  }

  private func startDirectorySource() {
    let descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .attrib, .link],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      self?.refresh()
    }
    source.setCancelHandler {
      close(descriptor)
    }
    directorySource = source
    source.resume()
  }

  private func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled, let self else { return }
        self.refresh()
      }
    }
  }

  private func updateState(_ nextState: CodexActivityState) {
    guard state != nextState else { return }
    state = nextState
    onStateChange?(nextState)
  }

  private func updateLastEventDate(_ date: Date?) {
    guard let date else { return }
    if lastEventDate == nil || date > lastEventDate! {
      lastEventDate = date
      onEventObserved?(date)
    }
  }
}
