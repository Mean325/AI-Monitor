import Darwin
import Foundation

private let defaultCodexActivityDirectoryURL = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("CodexLinxDisplay/activity", isDirectory: true)

private let defaultCodexSessionsDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".codex/sessions", isDirectory: true)

@MainActor
protocol CodexActivityMonitoring: AnyObject {
  var state: CodexActivityState { get }
  var lastEventDate: Date? { get }
  var onStateChange: ((CodexActivityState) -> Void)? { get set }
  var onEventObserved: ((Date) -> Void)? { get set }

  func start()
  func stop()
  func refresh()
}

@MainActor
final class CodexActivityMonitor: CodexActivityMonitoring {
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private let directoryURL: URL
  private let staleInterval: TimeInterval
  private let completedHoldInterval: TimeInterval
  private let orphanedHookGraceInterval: TimeInterval
  private let fileManager: FileManager
  private let sessionLogReader: CodexSessionLogActivityReader?
  private let eventQueue = DispatchQueue(
    label: "com.olivia.CodexLinxDisplay.activity-monitor",
    qos: .utility
  )
  private var directorySource: DispatchSourceFileSystemObject?
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false

  init(
    directoryURL: URL = defaultCodexActivityDirectoryURL,
    sessionsDirectoryURL: URL? = defaultCodexSessionsDirectoryURL,
    staleInterval: TimeInterval = 12 * 60 * 60,
    completedHoldInterval: TimeInterval = 10,
    orphanedHookGraceInterval: TimeInterval = 2 * 60,
    fileManager: FileManager = .default
  ) {
    self.directoryURL = directoryURL
    self.staleInterval = staleInterval
    self.completedHoldInterval = completedHoldInterval
    self.orphanedHookGraceInterval = orphanedHookGraceInterval
    self.fileManager = fileManager
    self.sessionLogReader = sessionsDirectoryURL.map {
      CodexSessionLogActivityReader(directoryURL: $0, fileManager: fileManager)
    }
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
      refresh()
      startDirectorySource()
      startPolling()
    } catch {
      updateState(.idle)
    }
  }

  func stop() {
    isStarted = false
    directorySource?.cancel()
    directorySource = nil
    pollingTask?.cancel()
    pollingTask = nil
  }

  func refresh() {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let hookRecords =
      (try? fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ))?
      .filter { $0.pathExtension == "json" }
      .compactMap { url -> CodexActivityRecord? in
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CodexActivityRecord.self, from: data)
      }
      ?? []

    // Codex Desktop persists lifecycle events in its local session JSONL even
    // when command hooks are untrusted or unavailable. Treat that durable log
    // as the primary fallback and keep hooks for permission/failure details.
    let sessionRecords = sessionLogReader?.records(
      modifiedAfter: Date().addingTimeInterval(-staleInterval)
    ) ?? []
    let records = reconciledRecords(
      hookRecords: hookRecords,
      sessionRecords: sessionRecords
    )

    updateLastEventDate(hookRecords.map(\.updatedAt).max())
    updateState(
      CodexActivityReducer.aggregate(
        records,
        staleInterval: staleInterval,
        completedHoldInterval: completedHoldInterval
      )
    )
  }

  private func reconciledRecords(
    hookRecords: [CodexActivityRecord],
    sessionRecords: [CodexActivityRecord],
    now: Date = Date()
  ) -> [CodexActivityRecord] {
    guard sessionLogReader != nil else { return hookRecords }

    let sessionRecordsByID = Dictionary(
      grouping: sessionRecords,
      by: \CodexActivityRecord.sessionID
    )

    let activeHookRecords = hookRecords.filter { hookRecord in
      guard hookRecord.state == .running else { return true }

      let matchingSessionRecords = sessionRecordsByID[hookRecord.sessionID] ?? []
      if matchingSessionRecords.contains(where: {
        $0.state == .finished && $0.updatedAt >= hookRecord.updatedAt
      }) {
        return false
      }

      // Hooks occasionally miss Stop/SessionEnd when a task is interrupted,
      // deleted, or moved. Session JSONL is the durable source of truth; keep
      // an unmatched hook briefly to cover log creation, then discard it so a
      // dead session cannot leave the traffic light yellow for 12 hours.
      let age = now.timeIntervalSince(hookRecord.updatedAt)
      if age <= orphanedHookGraceInterval { return true }
      return matchingSessionRecords.contains { $0.state == .running }
    }

    return activeHookRecords + sessionRecords
  }

  private func startDirectorySource() {
    let descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .attrib, .rename, .delete],
      queue: eventQueue
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.refresh()
      }
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

private final class CodexSessionLogActivityReader {
  private struct CachedRecord {
    let fileSize: UInt64
    let modificationDate: Date
    let record: CodexActivityRecord?
  }

  private struct SessionEnvelope: Decodable {
    struct Payload: Decodable {
      let type: String?
      let turnID: String?
      let message: String?
      let rateLimits: Limits?

      struct Limits: Decodable {
        struct Window: Decodable {
          let used_percent: Double?
          let resets_at: Double?
        }
        struct Credits: Decodable {
          let has_credits: Bool?
          let unlimited: Bool?
        }
        let limit_id: String?
        let primary: Window?
        let secondary: Window?
        let credits: Credits?

        var isMeaningfulCodexQuota: Bool {
          guard limit_id == nil || limit_id == "codex" else { return false }
          return primary != nil || secondary != nil
        }

        var exhaustedWindow: Window? {
          guard isMeaningfulCodexQuota,
            credits?.has_credits != true, credits?.unlimited != true else { return nil }
          return [primary, secondary].compactMap { $0 }
            .filter { ($0.used_percent ?? 0) >= 100 }
            .max { ($0.resets_at ?? .greatestFiniteMagnitude) < ($1.resets_at ?? .greatestFiniteMagnitude) }
        }
      }

      private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turn_id"
        case message
        case rateLimits = "rate_limits"
      }
    }

    let timestamp: String
    let type: String
    let payload: Payload?
  }

  private let directoryURL: URL
  private let fileManager: FileManager
  private var cache: [URL: CachedRecord] = [:]

  init(directoryURL: URL, fileManager: FileManager) {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
  }

  func records(modifiedAfter cutoff: Date) -> [CodexActivityRecord] {
    guard let enumerator = fileManager.enumerator(
      at: directoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var observedURLs = Set<URL>()
    var records: [CodexActivityRecord] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      guard
        let values = try? url.resourceValues(
          forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        ),
        values.isRegularFile == true,
        let modificationDate = values.contentModificationDate,
        modificationDate >= cutoff
      else {
        continue
      }

      observedURLs.insert(url)
      let fileSize = UInt64(values.fileSize ?? 0)
      let cached = cache[url]
      if cached?.fileSize == fileSize, cached?.modificationDate == modificationDate,
        cached?.record?.eventName != "token_count"
      {
        if let record = cached?.record { records.append(record) }
        continue
      }

      let record = readLatestRecord(
        from: url,
        sessionID: sessionID(from: url)
      )
      cache[url] = CachedRecord(
        fileSize: fileSize,
        modificationDate: modificationDate,
        record: record
      )
      if let record { records.append(record) }
    }

    cache = cache.filter { observedURLs.contains($0.key) }
    return records
  }

  private func readLatestRecord(from url: URL, sessionID: String) -> CodexActivityRecord? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    let fileSize = (try? handle.seekToEnd()) ?? 0
    let chunkSize: UInt64 = 256 * 1024
    var endOffset = fileSize
    var carriedData = Data()

    while endOffset > 0 {
      let startOffset = endOffset > chunkSize ? endOffset - chunkSize : 0
      do {
        try handle.seek(toOffset: startOffset)
        let chunk = try handle.read(upToCount: Int(endOffset - startOffset)) ?? Data()
        carriedData = chunk + carriedData
      } catch {
        return nil
      }

      let parsed = parseActivity(in: carriedData, sessionID: sessionID)
      if parsed.sawMeaningfulQuota || startOffset == 0 {
        return parsed.record
      }
      endOffset = startOffset
    }
    return nil
  }

  private func sessionID(from url: URL) -> String {
    let stem = url.deletingPathExtension().lastPathComponent
    guard stem.count >= 36 else { return url.lastPathComponent }
    let candidate = String(stem.suffix(36))
    guard UUID(uuidString: candidate) != nil else { return url.lastPathComponent }
    return candidate.lowercased()
  }

  private func parseActivity(in data: Data, sessionID: String) -> (
    record: CodexActivityRecord?, sawMeaningfulQuota: Bool
  ) {
    let decoder = JSONDecoder()
    var latestLifecycle: CodexActivityRecord?
    var exhaustedRecord: CodexActivityRecord?
    var expiredRecord: CodexActivityRecord?
    var sawMeaningfulQuota = false
    var lifecycleNewerThanQuota = false

    for line in data.split(separator: 0x0A).reversed() {
      guard
        let envelope = try? decoder.decode(SessionEnvelope.self, from: Data(line)),
        envelope.type == "event_msg",
        let eventName = envelope.payload?.type,
        let payload = envelope.payload,
        let updatedAt = parseDate(envelope.timestamp)
      else {
        continue
      }

      if !sawMeaningfulQuota,
        eventName == "token_count",
        let limits = payload.rateLimits,
        limits.isMeaningfulCodexQuota
      {
        sawMeaningfulQuota = true
        if let window = limits.exhaustedWindow {
          let resetPassed = window.resets_at.map { $0 <= Date().timeIntervalSince1970 } ?? false
          let record = CodexActivityRecord(
            schemaVersion: 2,
            sessionID: sessionID,
            turnID: payload.turnID,
            eventName: eventName,
            state: resetPassed ? .idle : .toolFailed,
            updatedAt: updatedAt
          )
          if resetPassed {
            expiredRecord = record
          } else {
            exhaustedRecord = record
          }
        }
      }

      if latestLifecycle == nil, let state = lifecycleState(for: payload) {
        latestLifecycle = CodexActivityRecord(
          schemaVersion: 2,
          sessionID: sessionID,
          turnID: payload.turnID,
          eventName: eventName,
          state: state,
          updatedAt: updatedAt
        )
        lifecycleNewerThanQuota = !sawMeaningfulQuota
      }

      if latestLifecycle != nil, sawMeaningfulQuota { break }
    }

    if let exhaustedRecord {
      return (exhaustedRecord, true)
    }
    if let expiredRecord, !lifecycleNewerThanQuota {
      return (expiredRecord, true)
    }
    if sawMeaningfulQuota, latestLifecycle?.state == .toolFailed, !lifecycleNewerThanQuota {
      return (
        CodexActivityRecord(
          schemaVersion: 2,
          sessionID: sessionID,
          turnID: latestLifecycle?.turnID,
          eventName: latestLifecycle?.eventName ?? "token_count",
          state: .idle,
          updatedAt: latestLifecycle?.updatedAt ?? Date()
        ),
        true
      )
    }
    return (latestLifecycle, sawMeaningfulQuota)
  }

  private func lifecycleState(for payload: SessionEnvelope.Payload) -> CodexActivityState? {
    switch payload.type {
    case "task_started": return .running
    case "task_complete", "turn_aborted": return .finished
    case "error":
      let message = payload.message?.lowercased() ?? ""
      if ["usage limit", "usage_limit", "quota", "用量", "额度"].contains(where: message.contains) {
        return .toolFailed
      }
      return nil
    default: return nil
    }
  }

  private func parseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}
