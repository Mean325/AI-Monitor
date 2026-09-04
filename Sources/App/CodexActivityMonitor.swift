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
    fileManager: FileManager = .default
  ) {
    self.directoryURL = directoryURL
    self.staleInterval = staleInterval
    self.completedHoldInterval = completedHoldInterval
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
    let records = hookRecords + sessionRecords

    updateLastEventDate(hookRecords.map(\.updatedAt).max())
    updateState(
      CodexActivityReducer.aggregate(
        records,
        staleInterval: staleInterval,
        completedHoldInterval: completedHoldInterval
      )
    )
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

        var hasAvailableQuota: Bool {
          guard limit_id == nil || limit_id == "codex" else { return false }
          if credits?.has_credits == true || credits?.unlimited == true { return true }
          let windows = [primary, secondary].compactMap { $0 }
          return !windows.isEmpty && windows.allSatisfy {
            guard let used = $0.used_percent else { return false }
            return used < 100
          }
        }

        var exhaustedWindow: Window? {
          guard limit_id == nil || limit_id == "codex",
            credits?.has_credits == false, credits?.unlimited != true else { return nil }
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

      let record = readLatestRecord(from: url)
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

  private func readLatestRecord(from url: URL) -> CodexActivityRecord? {
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

      if let record = latestRecord(in: carriedData, sessionID: url.lastPathComponent) {
        return record
      }
      endOffset = startOffset
    }
    return nil
  }

  private func latestRecord(in data: Data, sessionID: String) -> CodexActivityRecord? {
    let decoder = JSONDecoder()
    var quotaRecovered = false
    for line in data.split(separator: 0x0A).reversed() {
      if let envelope = try? decoder.decode(SessionEnvelope.self, from: Data(line)),
        envelope.type == "event_msg", envelope.payload?.type == "token_count",
        envelope.payload?.rateLimits?.hasAvailableQuota == true
      {
        quotaRecovered = true
      }
      guard
        let envelope = try? decoder.decode(SessionEnvelope.self, from: Data(line)),
        envelope.type == "event_msg",
        let eventName = envelope.payload?.type,
        let payload = envelope.payload,
        let state = state(for: payload),
        let updatedAt = parseDate(envelope.timestamp)
      else {
        continue
      }
      return CodexActivityRecord(
        schemaVersion: 2,
        sessionID: sessionID,
        turnID: envelope.payload?.turnID,
        eventName: eventName,
        state: quotaRecovered && state == .toolFailed ? .idle : state,
        updatedAt: updatedAt
      )
    }
    return nil
  }

  private func state(for payload: SessionEnvelope.Payload) -> CodexActivityState? {
    switch payload.type {
    case "task_started": return .running
    case "task_complete", "turn_aborted": return .finished
    case "token_count":
      guard let window = payload.rateLimits?.exhaustedWindow else { return nil }
      // No completion event may follow an exhausted quota. Treat it as failure
      // for both consumers of this monitor, until reset or a new task event.
      if let reset = window.resets_at, reset <= Date().timeIntervalSince1970 { return .idle }
      return .toolFailed
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
