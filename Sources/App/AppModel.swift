import AppKit
import Combine
import CryptoKit
import ServiceManagement

enum DisplayMode: String, CaseIterable, Identifiable {
  case codex
  case claudeCode
  case qoder
  case grok
  case customImage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex: return "Codex 用量"
    case .claudeCode: return "Claude Code"
    case .qoder: return "Qoder"
    case .grok: return "Grok"
    case .customImage: return "自定义图片"
    }
  }

  var symbol: String {
    switch self {
    case .codex: return "terminal.fill"
    case .claudeCode: return "sun.max.fill"
    case .qoder: return "wand.and.stars"
    case .grok: return "sparkles"
    case .customImage: return "photo"
    }
  }

  var isUsageMode: Bool {
    switch self {
    case .customImage: return false
    case .codex, .claudeCode, .qoder, .grok: return true
    }
  }
}

enum KeyboardConnectionState: Equatable {
  case disconnected
  case connected
  case pushFailed
}

enum MenuBarOriginalIconPosition: String, CaseIterable, Identifiable {
  case left, right, hidden
  var id: String { rawValue }
  var title: String {
    switch self {
    case .left: return "左侧展示"
    case .right: return "右侧展示"
    case .hidden: return "隐藏"
    }
  }
}

enum UsageQueryState: Equatable {
  case idle
  case querying
  case succeeded
  case failed
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var previewImage: NSImage?
  @Published private(set) var displayMode: DisplayMode
  @Published private(set) var selectedAIMode: DisplayMode
  @Published private(set) var usageCardColorScheme: UsageCardColorScheme
  @Published private(set) var usageCardDesign: UsageCardDesign
  @Published private(set) var customImageName: String?
  @Published private(set) var isSyncing = false
  @Published private(set) var statusText = "等待首次同步"
  @Published private(set) var lastError: String?
  @Published private(set) var lastUploadDate: Date?
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var launchAtLogin = false
  @Published private(set) var keyboardConnectionState: KeyboardConnectionState = .disconnected
  @Published private(set) var usageQueryState: UsageQueryState = .idle
  @Published private(set) var codexActivityState: CodexActivityState = .idle
  @Published private(set) var codexHookInstallationState: CodexHookInstallationState = .notInstalled
  @Published private(set) var claudeSnapshot: ClaudeCodeUsageSnapshot?
  @Published private(set) var claudeActivityState: CodexActivityState = .idle
  @Published private(set) var claudeHookInstallationState: CodexHookInstallationState = .notInstalled
  @Published private(set) var qoderSnapshot: QoderUsageSnapshot?
  @Published private(set) var qoderCreditSnapshot: QoderCreditSnapshot?
  @Published private(set) var qoderActivityState: CodexActivityState = .idle
  @Published private(set) var grokSnapshot: GrokUsageSnapshot?
  @Published private(set) var grokActivityState: CodexActivityState = .idle

  @Published var showTaskStatusInMenuBar: Bool {
    didSet {
      defaults.set(showTaskStatusInMenuBar, forKey: "showTaskStatusInMenuBar")
      if showTaskStatusInMenuBar { refreshSelectedActivity() }
    }
  }

  @Published var menuBarOriginalIconPosition: MenuBarOriginalIconPosition {
    didSet {
      defaults.set(menuBarOriginalIconPosition.rawValue, forKey: "menuBarOriginalIconPosition")
    }
  }

  var selectedActivityState: CodexActivityState? {
    switch displayMode {
    case .codex: return codexActivityState
    case .claudeCode: return claudeActivityState
    case .qoder: return qoderActivityState
    case .grok: return grokActivityState
    case .customImage: return nil
    }
  }

  var taskStatusDescription: String {
    "\(displayMode.title) · \(selectedActivityState?.title ?? "未选择 AI")"
  }

  func refreshSelectedActivity() {
    // Read a fresh snapshot even if the monitor has not emitted a change event.
    switch displayMode {
    case .codex:
      activityMonitor.refresh()
      applyCodexActivity(activityMonitor.state)
    case .claudeCode:
      claudeActivityMonitor.refresh()
      claudeActivityState = claudeActivityMonitor.state
    case .qoder:
      qoderActivityMonitor.refresh()
      qoderActivityState = qoderActivityMonitor.state
    case .grok:
      grokActivityMonitor.refresh()
      grokActivityState = grokActivityMonitor.state
    case .customImage: break
    }
  }

  @Published var endpoint: String {
    didSet {
      defaults.set(endpoint, forKey: Keys.endpoint)
      if endpoint != oldValue {
        keyboardConnectionState = .disconnected
        lastUploadedHash = nil
      }
    }
  }

  @Published var safeAreaHeight: Double {
    didSet {
      defaults.set(safeAreaHeight, forKey: Keys.safeAreaHeight)
      updatePreview()
    }
  }

  @Published var jpegQuality: Double {
    didSet {
      defaults.set(jpegQuality, forKey: Keys.jpegQuality)
      updatePreview()
    }
  }

  @Published private(set) var refreshIntervalSeconds: Int

  private let defaults: UserDefaults
  private let codexClient: any CodexRateLimitFetching
  private let imageAPIClient: any ImageUploading
  private let activityMonitor: any CodexActivityMonitoring
  private let hookInstaller: CodexHookInstaller
  private let claudeUsageClient: any ClaudeCodeUsageFetching
  private let claudeActivityMonitor: any CodexActivityMonitoring
  private let claudeHookInstaller: ClaudeCodeHookInstaller
  private let qoderUsageClient: any QoderUsageFetching
  private let qoderActivityMonitor: any CodexActivityMonitoring
  private let qoderLogClient: QoderLogClient
  private let grokUsageClient: any GrokUsageFetching
  private let grokActivityMonitor: any CodexActivityMonitoring
  private let customImageDirectory: URL
  private var schedulerTask: Task<Void, Never>?
  private var pendingModeActionTask: Task<Void, Never>?
  private var pendingActivityUploadTask: Task<Void, Never>?
  private var claudePendingActivityUploadTask: Task<Void, Never>?
  private var qoderPendingActivityUploadTask: Task<Void, Never>?
  private var grokPendingActivityUploadTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?
  private var lastUploadedHash: String?
  private var customSourceImage: NSImage?
  private var hasStarted = false
  private var activeAIMonitor: DisplayMode?

  init(
    defaults: UserDefaults = .standard,
    codexClient: any CodexRateLimitFetching = CodexRateLimitClient(),
    imageAPIClient: any ImageUploading = ImageAPIClient(),
    activityMonitor: (any CodexActivityMonitoring)? = nil,
    hookInstaller: CodexHookInstaller = CodexHookInstaller(),
    claudeUsageClient: any ClaudeCodeUsageFetching = ClaudeCodeUsageClient(),
    claudeActivityMonitor: (any CodexActivityMonitoring)? = nil,
    claudeHookInstaller: ClaudeCodeHookInstaller = ClaudeCodeHookInstaller(),
    qoderUsageClient: any QoderUsageFetching = QoderUsageClient(),
    qoderActivityMonitor: (any CodexActivityMonitoring)? = nil,
    grokUsageClient: any GrokUsageFetching = GrokUsageClient(),
    grokActivityMonitor: (any CodexActivityMonitoring)? = nil,
    customImageDirectory: URL? = nil
  ) {
    let resolvedActivityMonitor = activityMonitor ?? CodexActivityMonitor()
    let resolvedClaudeActivityMonitor = claudeActivityMonitor
      ?? CodexActivityMonitor(directoryURL: Self.defaultClaudeActivityDirectoryURL, sessionsDirectoryURL: nil)
    let resolvedQoderActivityMonitor = qoderActivityMonitor ?? QoderActivityMonitor()
    let resolvedGrokActivityMonitor = grokActivityMonitor ?? GrokActivityMonitor()
    self.defaults = defaults
    showTaskStatusInMenuBar = defaults.bool(forKey: "showTaskStatusInMenuBar")
    menuBarOriginalIconPosition = MenuBarOriginalIconPosition(
      rawValue: defaults.string(forKey: "menuBarOriginalIconPosition") ?? ""
    ) ?? .left
    self.codexClient = codexClient
    self.imageAPIClient = imageAPIClient
    self.activityMonitor = resolvedActivityMonitor
    self.hookInstaller = hookInstaller
    self.claudeUsageClient = claudeUsageClient
    self.claudeActivityMonitor = resolvedClaudeActivityMonitor
    self.claudeHookInstaller = claudeHookInstaller
    self.qoderUsageClient = qoderUsageClient
    self.qoderActivityMonitor = resolvedQoderActivityMonitor
    self.qoderLogClient = QoderLogClient()
    self.grokUsageClient = grokUsageClient
    self.grokActivityMonitor = resolvedGrokActivityMonitor
    self.customImageDirectory = customImageDirectory ?? Self.defaultCustomImageDirectory
    codexActivityState = resolvedActivityMonitor.state
    codexHookInstallationState = hookInstaller.installationState()
    claudeActivityState = resolvedClaudeActivityMonitor.state
    claudeHookInstallationState = claudeHookInstaller.installationState()
    qoderActivityState = resolvedQoderActivityMonitor.state
    grokActivityState = resolvedGrokActivityMonitor.state

    endpoint = defaults.string(forKey: Keys.endpoint) ?? "http://192.168.31.71/image/upload"
    refreshIntervalSeconds = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 300
    let storedMode = DisplayMode(
      rawValue: defaults.string(forKey: Keys.displayMode) ?? ""
    ) ?? .codex
    displayMode = storedMode
    let storedAI = DisplayMode(rawValue: defaults.string(forKey: "selectedAIMode") ?? "")
    selectedAIMode = storedMode.isUsageMode ? storedMode
      : (storedAI?.isUsageMode == true ? storedAI! : .codex)
    usageCardColorScheme = UsageCardColorScheme(
      rawValue: defaults.string(forKey: Keys.usageCardColorScheme)
        ?? defaults.string(forKey: Keys.legacyUsageCardStyle)
        ?? ""
    ) ?? .deepSpace
    usageCardDesign = UsageCardDesign(
      rawValue: defaults.string(forKey: Keys.usageCardDesign) ?? ""
    ) ?? .classic

    let storedSafeArea = defaults.object(forKey: Keys.safeAreaHeight) as? Double
    safeAreaHeight = storedSafeArea ?? Double(UsageCardLayout.defaultSafeArea)

    let storedQuality = defaults.object(forKey: Keys.jpegQuality) as? Double
    jpegQuality = storedQuality ?? 0.9

    if let path = defaults.string(forKey: Keys.customImagePath),
      let image = NSImage(contentsOfFile: path)
    {
      customSourceImage = image
      customImageName =
        defaults.string(forKey: Keys.customImageName)
        ?? URL(fileURLWithPath: path).lastPathComponent
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled
    updatePreview()
    if displayMode == .customImage {
      statusText = customSourceImage == nil ? "请选择一张图片" : "图片模式待推送"
    }
  }

  deinit {
    schedulerTask?.cancel()
    pendingModeActionTask?.cancel()
    pendingActivityUploadTask?.cancel()
    claudePendingActivityUploadTask?.cancel()
    qoderPendingActivityUploadTask?.cancel()
    grokPendingActivityUploadTask?.cancel()
    if let wakeObserver {
      NotificationCenter.default.removeObserver(wakeObserver)
    }
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    activityMonitor.onStateChange = { [weak self] state in
      self?.handleCodexActivityChange(state)
    }
    activityMonitor.onEventObserved = { [weak self] date in
      self?.handleCodexHookEvent(date)
    }
    applyCodexActivity(activityMonitor.state)
    if let lastEventDate = activityMonitor.lastEventDate {
      handleCodexHookEvent(lastEventDate)
    }

    claudeActivityMonitor.onStateChange = { [weak self] state in
      self?.handleClaudeActivityChange(state)
    }
    claudeActivityMonitor.onEventObserved = { [weak self] date in
      self?.handleClaudeHookEvent(date)
    }
    claudeActivityState = claudeActivityMonitor.state
    if let lastEventDate = claudeActivityMonitor.lastEventDate {
      handleClaudeHookEvent(lastEventDate)
    }

    qoderActivityMonitor.onStateChange = { [weak self] state in
      self?.handleQoderActivityChange(state)
    }
    qoderActivityState = qoderActivityMonitor.state

    grokActivityMonitor.onStateChange = { [weak self] state in
      self?.handleGrokActivityChange(state)
    }
    grokActivityState = grokActivityMonitor.state
    activateSelectedMonitor()
    updatePreview()

    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.isUsageMode {
          await self.synchronize(upload: true, forceUpload: true)
        } else {
          await self.uploadCustomImage(forceUpload: true)
        }
      }
    }

    if isUsageMode {
      usageQueryState = .querying
      restartScheduler(uploadImmediately: true)
    } else if customSourceImage != nil {
      scheduleCurrentModeAction()
    }
  }

  func setRefreshInterval(_ seconds: Int) {
    guard refreshIntervalSeconds != seconds else { return }
    refreshIntervalSeconds = seconds
    defaults.set(seconds, forKey: Keys.refreshInterval)
    if isUsageMode {
      restartScheduler(uploadImmediately: false)
    }
  }

  func setDisplayMode(_ mode: DisplayMode) {
    if mode.isUsageMode {
      selectedAIMode = mode
      defaults.set(mode.rawValue, forKey: "selectedAIMode")
    }
    guard displayMode != mode else { return }

    displayMode = mode
    activateSelectedMonitor()
    refreshSelectedActivity()
    defaults.set(mode.rawValue, forKey: Keys.displayMode)
    lastUploadedHash = nil
    lastError = nil
    schedulerTask?.cancel()
    schedulerTask = nil
    pendingModeActionTask?.cancel()
    pendingActivityUploadTask?.cancel()
    claudePendingActivityUploadTask?.cancel()
    qoderPendingActivityUploadTask?.cancel()
    grokPendingActivityUploadTask?.cancel()
    updatePreview()

    switch mode {
    case .customImage:
      usageQueryState = .idle
      statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
    case .codex:
      usageQueryState = .querying
      statusText = "准备读取 Codex"
    case .claudeCode:
      usageQueryState = .querying
      statusText = "准备读取 Claude Code"
    case .qoder:
      usageQueryState = .querying
      statusText = "准备读取 Qoder"
    case .grok:
      usageQueryState = .querying
      statusText = "准备读取 Grok 余量"
    }

    if hasStarted {
      scheduleCurrentModeAction()
    }
  }

  func setSelectedAI(_ mode: DisplayMode) {
    guard mode.isUsageMode else { return }
    selectedAIMode = mode
    defaults.set(mode.rawValue, forKey: "selectedAIMode")
    if displayMode.isUsageMode { setDisplayMode(mode) }
    activateSelectedMonitor()
  }

  private func activateSelectedMonitor() {
    guard hasStarted, activeAIMonitor != selectedAIMode else { return }
    activityMonitor.stop()
    claudeActivityMonitor.stop()
    qoderActivityMonitor.stop()
    grokActivityMonitor.stop()
    activeAIMonitor = selectedAIMode
    switch selectedAIMode {
    case .codex:
      activityMonitor.start()
      applyCodexActivity(activityMonitor.state)
    case .claudeCode:
      claudeActivityMonitor.start()
      claudeActivityState = claudeActivityMonitor.state
    case .qoder:
      qoderActivityMonitor.start()
      qoderActivityState = qoderActivityMonitor.state
    case .grok:
      grokActivityMonitor.start()
      grokActivityState = grokActivityMonitor.state
    case .customImage: break
    }
  }

  func setUsageCardColorScheme(_ colorScheme: UsageCardColorScheme) {
    guard usageCardColorScheme != colorScheme else { return }

    usageCardColorScheme = colorScheme
    defaults.set(colorScheme.rawValue, forKey: Keys.usageCardColorScheme)
    lastUploadedHash = nil
    updatePreview()

    if hasStarted, isUsageMode {
      scheduleCurrentModeAction()
    }
  }

  func setUsageCardDesign(_ design: UsageCardDesign) {
    guard usageCardDesign != design else { return }

    usageCardDesign = design
    defaults.set(design.rawValue, forKey: Keys.usageCardDesign)
    lastUploadedHash = nil
    updatePreview()

    if hasStarted, isUsageMode {
      scheduleCurrentModeAction()
    }
  }

  func selectCustomImage(at url: URL) {
    guard let image = NSImage(contentsOf: url) else {
      lastError = "无法读取所选图片，请选择常见的图片格式。"
      statusText = "图片读取失败"
      return
    }

    do {
      let storedURL = try persistCustomImage(image)
      customSourceImage = image
      customImageName = url.lastPathComponent
      defaults.set(storedURL.path, forKey: Keys.customImagePath)
      defaults.set(url.lastPathComponent, forKey: Keys.customImageName)
      lastError = nil
    } catch {
      lastError = "无法保存所选图片：\(error.localizedDescription)"
      statusText = "图片保存失败"
      return
    }

    if displayMode != .customImage {
      setDisplayMode(.customImage)
    } else {
      lastUploadedHash = nil
      updatePreview()
      statusText = "图片已准备"
      if hasStarted {
        scheduleCurrentModeAction()
      }
    }
  }

  func refreshOnly() {
    guard isUsageMode else {
      statusText = "图片模式下用量刷新已暂停"
      return
    }
    Task { await synchronize(upload: false, forceUpload: false) }
  }

  func pushNow() {
    if isUsageMode {
      Task { await synchronize(upload: true, forceUpload: true) }
    } else {
      scheduleCurrentModeAction()
    }
  }

  func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = enabled
      lastError = nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      lastError = "无法修改开机启动：\(error.localizedDescription)"
      statusText = "设置失败"
    }
  }

  func installCodexActivityHooks() {
    do {
      try hookInstaller.install()
      codexHookInstallationState = .configured
      lastError = nil
      statusText = "状态监控 Hook 已配置 · 请在 Codex 中信任"
    } catch {
      codexHookInstallationState = .failed(error.localizedDescription)
      lastError = error.localizedDescription
      statusText = "状态监控 Hook 安装失败"
    }
  }

  var codexHookStatusText: String {
    switch codexHookInstallationState {
    case .notInstalled:
      return "未安装"
    case .configured:
      return "已配置 · 待 Codex 信任或验证"
    case .active(let date):
      return "已生效 · \(Self.dateTimeFormatter.string(from: date))"
    case .failed(let message):
      return message
    }
  }

  func installClaudeCodeActivityHooks() {
    do {
      try claudeHookInstaller.install()
      claudeHookInstallationState = .configured
      lastError = nil
      statusText = "Claude Code 状态监控 Hook 已配置"
    } catch {
      claudeHookInstallationState = .failed(error.localizedDescription)
      lastError = error.localizedDescription
      statusText = "Claude Code Hook 安装失败"
    }
  }

  var claudeHookStatusText: String {
    switch claudeHookInstallationState {
    case .notInstalled:
      return "未安装"
    case .configured:
      return "已配置 · 待 Claude Code 生效"
    case .active(let date):
      return "已生效 · \(Self.dateTimeFormatter.string(from: date))"
    case .failed(let message):
      return message
    }
  }

  var qoderDataStatusText: String {
    if let monitor = qoderActivityMonitor as? QoderActivityMonitor,
      !monitor.projectsDirectoryExists
    {
      return "未找到 ~/.qoder/projects"
    }
    if let lastEventDate = qoderActivityMonitor.lastEventDate {
      return "监控中 · \(Self.dateTimeFormatter.string(from: lastEventDate))"
    }
    return "监控中 · 等待会话活动"
  }

  var grokDataStatusText: String {
    if let monitor = grokActivityMonitor as? GrokActivityMonitor,
      !monitor.authDirectoryExists
    {
      return "未找到 ~/.grok/auth.json"
    }
    if let lastEventDate = grokActivityMonitor.lastEventDate {
      return "监控中 · \(Self.dateTimeFormatter.string(from: lastEventDate))"
    }
    return "已连接 · 等待 Grok 会话"
  }

  func synchronize(upload: Bool, forceUpload: Bool) async {
    guard isUsageMode, !isSyncing else { return }
    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    var didCompleteQuery = false
    usageQueryState = .querying
    lastError = nil
    statusText = upload ? "正在同步并推送…" : "正在读取用量…"

    defer { isSyncing = false }

    do {
      let rendered: RenderedUsageCard
      switch displayMode {
      case .codex:
        let latestSnapshot = try await codexClient.fetch()
        guard displayMode == .codex else {
          usageQueryState = .idle
          statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
          return
        }
        didCompleteQuery = true
        usageQueryState = .succeeded
        snapshot = latestSnapshot
        applyCodexActivity(activityMonitor.state)
        lastRefreshDate = Date()
        rendered = try UsageCardRenderer.render(
          snapshot: latestSnapshot,
          activityState: codexActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        )
      case .claudeCode:
        let latestSnapshot = try await claudeUsageClient.fetch()
        guard displayMode == .claudeCode else {
          usageQueryState = .idle
          statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
          return
        }
        didCompleteQuery = true
        usageQueryState = .succeeded
        claudeSnapshot = latestSnapshot
        lastRefreshDate = Date()
        rendered = try UsageCardRenderer.render(
          claudeSnapshot: latestSnapshot,
          activityState: claudeActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        )
      case .qoder:
        let latestSnapshot = try await qoderUsageClient.fetch()
        guard displayMode == .qoder else {
          usageQueryState = .idle
          statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
          return
        }
        didCompleteQuery = true
        usageQueryState = .succeeded
        qoderSnapshot = latestSnapshot
        // 从日志中获取 credit 额度数据
        if let creditSnapshot = try? qoderLogClient.fetchSynchronously(), creditSnapshot.hasData {
          qoderCreditSnapshot = creditSnapshot
        }
        lastRefreshDate = Date()
        rendered = try UsageCardRenderer.render(
          qoderSnapshot: latestSnapshot,
          creditSnapshot: qoderCreditSnapshot,
          activityState: qoderActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        )
      case .grok:
        let latestSnapshot = try await grokUsageClient.fetch()
        guard displayMode == .grok else {
          usageQueryState = .idle
          statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
          return
        }
        didCompleteQuery = true
        usageQueryState = .succeeded
        grokSnapshot = latestSnapshot
        lastRefreshDate = Date()
        rendered = try UsageCardRenderer.render(
          grokSnapshot: latestSnapshot,
          activityState: grokActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        )
      case .customImage:
        return
      }
      previewImage = rendered.image

      guard upload else {
        statusText = "用量已刷新"
        return
      }

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      if !forceUpload, hash == lastUploadedHash {
        statusText = "数据未变化"
        return
      }

      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      lastUploadedHash = hash
      lastUploadDate = Date()
      statusText = "推送成功 · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      if isUsageMode {
        if !didCompleteQuery {
          usageQueryState = .failed
        }
        lastError = error.localizedDescription
        statusText = "同步失败"
      } else {
        usageQueryState = .idle
        lastError = nil
        statusText = customSourceImage == nil ? "请选择一张图片" : "用量刷新已暂停"
      }
    }
  }

  func uploadCustomImage(forceUpload: Bool) async {
    guard displayMode == .customImage, !isSyncing else { return }
    guard let customSourceImage else {
      lastError = "请先选择要显示的图片。"
      statusText = "尚未选择图片"
      return
    }

    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    lastError = nil
    statusText = "正在推送图片…"
    defer { isSyncing = false }

    do {
      let rendered = try CustomImageRenderer.render(
        image: customSourceImage,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      if !forceUpload, hash == lastUploadedHash {
        statusText = "图片未变化"
        return
      }

      guard displayMode == .customImage else { return }
      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      guard displayMode == .customImage else { return }
      lastUploadedHash = hash
      lastUploadDate = Date()
      statusText = "图片推送成功 · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      if displayMode == .customImage {
        lastError = error.localizedDescription
        statusText = "图片推送失败"
      }
    }
  }

  var lastUploadText: String {
    guard let lastUploadDate else { return "尚未推送" }
    return Self.dateTimeFormatter.string(from: lastUploadDate)
  }

  private func connectionStateAfterUploadFailure(
    _ error: Error,
    previousState: KeyboardConnectionState
  ) -> KeyboardConnectionState {
    guard let apiError = error as? ImageAPIError else {
      return previousState == .disconnected ? .disconnected : .pushFailed
    }

    switch apiError {
    case .invalidResponse, .rejected:
      return .pushFailed
    case .transport:
      return previousState == .disconnected ? .disconnected : .pushFailed
    case .invalidURL, .connectionFailed, .timedOut, .networkUnavailable:
      return .disconnected
    }
  }

  var lastRefreshText: String {
    guard let lastRefreshDate else { return "尚未刷新" }
    return Self.dateTimeFormatter.string(from: lastRefreshDate)
  }

  private func handleCodexActivityChange(_ state: CodexActivityState) {
    applyCodexActivity(state, uploadIfChanged: true)
  }

  private func applyCodexActivity(
    _ state: CodexActivityState,
    uploadIfChanged: Bool = false
  ) {
    let resolved = snapshot?.isQuotaExhausted == true ? .toolFailed : state
    guard codexActivityState != resolved else { return }
    codexActivityState = resolved
    updatePreview()
    guard uploadIfChanged, hasStarted, displayMode == .codex else { return }
    scheduleCodexActivityUpload()
  }

  private func handleCodexHookEvent(_ date: Date) {
    guard codexHookInstallationState.isConfigured else { return }
    if case .active(let currentDate) = codexHookInstallationState,
      currentDate >= date
    {
      return
    }
    codexHookInstallationState = .active(date)
  }

  private func scheduleCodexActivityUpload() {
    pendingActivityUploadTask?.cancel()
    pendingActivityUploadTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == .codex else { return }
      await self.uploadCurrentCodexActivityCard()
    }
  }

  private func uploadCurrentCodexActivityCard() async {
    guard displayMode == .codex, !isSyncing else { return }
    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    defer { isSyncing = false }

    do {
      let rendered = try UsageCardRenderer.render(
        snapshot: snapshot,
        activityState: codexActivityState,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality,
        colorScheme: usageCardColorScheme,
        design: usageCardDesign
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      guard hash != lastUploadedHash else { return }

      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      lastUploadedHash = hash
      lastUploadDate = Date()
      lastError = nil
      statusText = "\(codexActivityState.title) · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      lastError = error.localizedDescription
      statusText = "状态卡片推送失败"
    }
  }

  private func handleClaudeActivityChange(_ state: CodexActivityState) {
    guard claudeActivityState != state else { return }
    claudeActivityState = state
    updatePreview()

    guard hasStarted, displayMode == .claudeCode else { return }
    scheduleClaudeActivityUpload()
  }

  private func handleQoderActivityChange(_ state: CodexActivityState) {
    guard qoderActivityState != state else { return }
    qoderActivityState = state
    updatePreview()

    guard hasStarted, displayMode == .qoder else { return }
    scheduleQoderActivityUpload()
  }

  private func handleGrokActivityChange(_ state: CodexActivityState) {
    guard grokActivityState != state else { return }
    grokActivityState = state
    updatePreview()

    guard hasStarted, displayMode == .grok else { return }
    scheduleGrokActivityUpload()
  }

  private func scheduleGrokActivityUpload() {
    grokPendingActivityUploadTask?.cancel()
    grokPendingActivityUploadTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == .grok else { return }
      await self.uploadCurrentGrokActivityCard()
    }
  }

  private func uploadCurrentGrokActivityCard() async {
    guard displayMode == .grok, !isSyncing else { return }
    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    defer { isSyncing = false }

    do {
      let rendered = try UsageCardRenderer.render(
        grokSnapshot: grokSnapshot,
        activityState: grokActivityState,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality,
        colorScheme: usageCardColorScheme,
        design: usageCardDesign
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      guard hash != lastUploadedHash else { return }

      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      lastUploadedHash = hash
      lastUploadDate = Date()
      lastError = nil
      statusText = "\(grokActivityState.title) · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      lastError = error.localizedDescription
      statusText = "状态卡片推送失败"
    }
  }

  private func scheduleQoderActivityUpload() {
    qoderPendingActivityUploadTask?.cancel()
    qoderPendingActivityUploadTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == .qoder else { return }
      await self.uploadCurrentQoderActivityCard()
    }
  }

  private func uploadCurrentQoderActivityCard() async {
    guard displayMode == .qoder, !isSyncing else { return }
    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    defer { isSyncing = false }

    do {
      let rendered = try UsageCardRenderer.render(
        qoderSnapshot: qoderSnapshot,
        creditSnapshot: qoderCreditSnapshot,
        activityState: qoderActivityState,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality,
        colorScheme: usageCardColorScheme,
        design: usageCardDesign
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      guard hash != lastUploadedHash else { return }

      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      lastUploadedHash = hash
      lastUploadDate = Date()
      lastError = nil
      statusText = "\(qoderActivityState.title) · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      lastError = error.localizedDescription
      statusText = "状态卡片推送失败"
    }
  }

  private func handleClaudeHookEvent(_ date: Date) {
    guard claudeHookInstallationState.isConfigured else { return }
    if case .active(let currentDate) = claudeHookInstallationState,
      currentDate >= date
    {
      return
    }
    claudeHookInstallationState = .active(date)
  }

  private func scheduleClaudeActivityUpload() {
    claudePendingActivityUploadTask?.cancel()
    claudePendingActivityUploadTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == .claudeCode else { return }
      await self.uploadCurrentClaudeActivityCard()
    }
  }

  private func uploadCurrentClaudeActivityCard() async {
    guard displayMode == .claudeCode, !isSyncing else { return }
    isSyncing = true
    var didStartUpload = false
    var connectionStateBeforeUpload: KeyboardConnectionState?
    defer { isSyncing = false }

    do {
      let rendered = try UsageCardRenderer.render(
        claudeSnapshot: claudeSnapshot,
        activityState: claudeActivityState,
        safeAreaHeight: safeAreaHeight,
        jpegQuality: jpegQuality,
        colorScheme: usageCardColorScheme,
        design: usageCardDesign
      )
      previewImage = rendered.image

      let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
      guard hash != lastUploadedHash else { return }

      connectionStateBeforeUpload = keyboardConnectionState
      didStartUpload = true
      let uploadEndpoint = endpoint
      let result = try await imageAPIClient.upload(rendered.data, endpoint: uploadEndpoint)
      keyboardConnectionState = endpoint == uploadEndpoint ? .connected : .disconnected
      lastUploadedHash = hash
      lastUploadDate = Date()
      lastError = nil
      statusText = "\(claudeActivityState.title) · HTTP \(result.statusCode)"
    } catch {
      if didStartUpload {
        keyboardConnectionState = connectionStateAfterUploadFailure(
          error,
          previousState: connectionStateBeforeUpload ?? .disconnected
        )
      }
      lastError = error.localizedDescription
      statusText = "状态卡片推送失败"
    }
  }

  private func restartScheduler(uploadImmediately: Bool) {
    schedulerTask?.cancel()
    guard isUsageMode else {
      schedulerTask = nil
      return
    }

    schedulerTask = Task { [weak self] in
      guard let self else { return }
      if uploadImmediately {
        await self.synchronize(upload: true, forceUpload: true)
      }

      while !Task.isCancelled {
        let interval = self.refreshIntervalSeconds
        try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        guard !Task.isCancelled, self.isUsageMode else { return }
        await self.synchronize(upload: true, forceUpload: false)
      }
    }
  }

  private func updatePreview() {
    do {
      switch displayMode {
      case .codex:
        previewImage = try UsageCardRenderer.render(
          snapshot: snapshot ?? .sample,
          activityState: codexActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        ).image
      case .claudeCode:
        previewImage = try UsageCardRenderer.render(
          claudeSnapshot: claudeSnapshot ?? .sample,
          activityState: claudeActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        ).image
      case .qoder:
        previewImage = try UsageCardRenderer.render(
          qoderSnapshot: qoderSnapshot ?? .sample,
          creditSnapshot: qoderCreditSnapshot,
          activityState: qoderActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        ).image
      case .grok:
        previewImage = try UsageCardRenderer.render(
          grokSnapshot: grokSnapshot ?? .sample,
          activityState: grokActivityState,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality,
          colorScheme: usageCardColorScheme,
          design: usageCardDesign
        ).image
      case .customImage:
        guard let customSourceImage else {
          previewImage = nil
          return
        }
        previewImage = try CustomImageRenderer.render(
          image: customSourceImage,
          safeAreaHeight: safeAreaHeight,
          jpegQuality: jpegQuality
        ).image
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func scheduleCurrentModeAction() {
    pendingModeActionTask?.cancel()
    let expectedMode = displayMode

    pendingModeActionTask = Task { [weak self] in
      guard let self else { return }
      while self.isSyncing {
        do {
          try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, self.displayMode == expectedMode else { return }

      if expectedMode == .customImage {
        await self.uploadCustomImage(forceUpload: true)
      } else {
        self.restartScheduler(uploadImmediately: true)
      }
    }
  }

  private func persistCustomImage(_ image: NSImage) throws -> URL {
    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      throw UsageCardRendererError.encodingFailed
    }

    try FileManager.default.createDirectory(
      at: customImageDirectory,
      withIntermediateDirectories: true
    )
    let storedURL = customImageDirectory.appendingPathComponent("custom-image.png")
    try pngData.write(to: storedURL, options: .atomic)
    return storedURL
  }

  private var isUsageMode: Bool {
    displayMode.isUsageMode
  }

  private enum Keys {
    static let endpoint = "imageAPIEndpoint"
    static let refreshInterval = "refreshIntervalSeconds"
    static let safeAreaHeight = "safeAreaHeight"
    static let jpegQuality = "jpegQuality"
    static let displayMode = "displayMode"
    static let usageCardColorScheme = "usageCardColorScheme"
    static let usageCardDesign = "usageCardDesign"
    static let legacyUsageCardStyle = "usageCardStyle"
    static let customImagePath = "customImagePath"
    static let customImageName = "customImageName"
  }

  private static let defaultCustomImageDirectory = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("CodexLinxDisplay", isDirectory: true)

  private static let defaultClaudeActivityDirectoryURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("CodexLinxDisplay/claude-activity", isDirectory: true)

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm:ss"
    return formatter
  }()
}
