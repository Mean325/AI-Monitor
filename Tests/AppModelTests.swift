import AppKit
import SwiftUI
import XCTest

@testable import CodexLinxDisplay

final class AppModelTests: XCTestCase {
  @MainActor
  func testGlassPopupsSupportLightAndDarkAppearance() throws {
    let suite = "GlassAppearanceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    for dark in [false, true] {
        let view = MenuBarContentView(model: model)
          .environment(\.colorScheme, dark ? .dark : .light)
        let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
        XCTAssertEqual(image.size.width, 320)
        XCTAssertGreaterThan(image.size.height, 200)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
          uniformTypeIdentifier: "public.png")
        attachment.name = "Glass-popup-\(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
  }

  @MainActor
  func testOnlySelectedAIMonitorRuns() throws {
    let suite = "SelectedMonitorTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let codex = FakeCodexActivityMonitor()
    let claude = FakeCodexActivityMonitor()
    let qoder = FakeCodexActivityMonitor()
    let grok = FakeCodexActivityMonitor()
    let model = AppModel(defaults: defaults, codexClient: FakeCodexClient(),
      imageAPIClient: FakeImageClient(), activityMonitor: codex,
      claudeActivityMonitor: claude, qoderActivityMonitor: qoder, grokActivityMonitor: grok)
    model.start()
    XCTAssertTrue(codex.isStarted)
    XCTAssertFalse(claude.isStarted)
    XCTAssertFalse(qoder.isStarted)
    XCTAssertFalse(grok.isStarted)
    model.setSelectedAI(.grok)
    XCTAssertFalse(codex.isStarted)
    XCTAssertTrue(grok.isStarted)
    model.setDisplayMode(.customImage)
    model.setSelectedAI(.qoder)
    XCTAssertFalse(grok.isStarted)
    XCTAssertTrue(qoder.isStarted)
    XCTAssertFalse(claude.isStarted)
  }

  @MainActor
  func testAISelectionSurvivesCustomImageModeAndRelaunch() throws {
    let suite = "AISelectionTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("grok", forKey: "displayMode")
    let model = AppModel(defaults: defaults)
    XCTAssertEqual(model.selectedAIMode, .grok)
    model.setDisplayMode(.customImage)
    model.setSelectedAI(.qoder)
    XCTAssertEqual(model.displayMode, .customImage)
    let restored = AppModel(defaults: defaults)
    XCTAssertEqual(restored.selectedAIMode, .qoder)
    restored.setDisplayMode(restored.selectedAIMode)
    XCTAssertEqual(restored.displayMode, .qoder)
    restored.setSelectedAI(.claudeCode)
    XCTAssertEqual(restored.displayMode, .claudeCode)
    restored.setSelectedAI(.customImage)
    XCTAssertEqual(restored.selectedAIMode, .claudeCode)
  }

  @MainActor
  func testReorganizedSettingsPanesRender() throws {
    XCTAssertEqual(SettingsPane.allCases.map(\.title), ["状态监控", "Linx68推送", "通用"])
    let suite = "SettingsLayoutTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    for pane in SettingsPane.allCases {
      let renderer = ImageRenderer(content: SettingsView(model: model, initialPane: pane))
      let image = try XCTUnwrap(renderer.nsImage)
      XCTAssertEqual(image.size, NSSize(width: 890, height: 760))
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
      attachment.name = "Settings-\(pane.rawValue)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor
  func testOriginalIconPositionPersistsAndDefaultsToLeft() throws {
    let suite = "IconPositionTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    XCTAssertEqual(model.menuBarOriginalIconPosition, .left)
    for position in MenuBarOriginalIconPosition.allCases {
      model.menuBarOriginalIconPosition = position
      XCTAssertEqual(AppModel(defaults: defaults).menuBarOriginalIconPosition, position)
    }
    defaults.set("invalid", forKey: "menuBarOriginalIconPosition")
    XCTAssertEqual(AppModel(defaults: defaults).menuBarOriginalIconPosition, .left)
  }

  func testOriginalIconLayoutsKeepLightsVisible() throws {
    for position in MenuBarOriginalIconPosition.allCases {
      let image = MenuBarStatusIcon.makeCombinedImage(connectionState: .connected,
        displayMode: .codex, showTaskStatus: true, activityState: .idle,
        iconPosition: position)
      let width: CGFloat = position == .hidden ? 60 : 90
      XCTAssertEqual(image.size.width, width)
      XCTAssertFalse(image.isTemplate)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
      let center: CGFloat = position == .left ? 82 : 52
      let x = Int(center * CGFloat(bitmap.pixelsWide) / width)
      let color = try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
      XCTAssertGreaterThan(color.greenComponent, color.redComponent)
      let disabled = MenuBarStatusIcon.makeCombinedImage(connectionState: .connected,
        displayMode: .codex, showTaskStatus: false, activityState: .idle,
        iconPosition: position)
      XCTAssertEqual(disabled.size.width, 18)
      XCTAssertTrue(disabled.isTemplate)
    }
  }

  func testMenuBarImageIncludesColoredLightsWhenEnabled() throws {
    let disabled = MenuBarStatusIcon.makeCombinedImage(connectionState: .connected,
      displayMode: .codex, showTaskStatus: false, activityState: .idle)
    XCTAssertEqual(disabled.size.width, 18)
    XCTAssertTrue(disabled.isTemplate)
    for state in [CodexActivityState.idle, .running, .toolFailed] {
      let image = MenuBarStatusIcon.makeCombinedImage(connectionState: .disconnected,
        displayMode: .codex, showTaskStatus: true, activityState: state)
      XCTAssertEqual(image.size.width, 90)
      XCTAssertFalse(image.isTemplate)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
      let index = try XCTUnwrap(TaskTrafficLight.activeIndex(state: state, mode: .codex))
      let x = Int(CGFloat(38 + index * 22) * CGFloat(bitmap.pixelsWide) / 90)
      let color = try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
      XCTAssertGreaterThan(color.alphaComponent, 0.9)
      if state == .idle { XCTAssertGreaterThan(color.greenComponent, color.redComponent) }
      if state == .running { XCTAssertGreaterThan(color.greenComponent, color.blueComponent) }
      if state == .toolFailed { XCTAssertGreaterThan(color.redComponent, color.greenComponent) }
    }
  }

  @MainActor
  func testEnablingTaskLightsReadsCurrentStateWithoutWaitingForEvent() throws {
    let suite = "TaskMonitoringTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let monitor = FakeCodexActivityMonitor()
    let grokMonitor = FakeCodexActivityMonitor()
    let model = AppModel(defaults: defaults, activityMonitor: monitor,
                         grokActivityMonitor: grokMonitor)
    monitor.stateOnRefresh = .running
    model.showTaskStatusInMenuBar = true
    XCTAssertEqual(model.selectedActivityState, .running)
    monitor.stateOnRefresh = .awaitingAuthorization
    model.showTaskStatusInMenuBar = false
    model.showTaskStatusInMenuBar = true
    XCTAssertEqual(model.selectedActivityState, .awaitingAuthorization)
    model.showTaskStatusInMenuBar = false
    monitor.stateOnRefresh = .finished
    model.showTaskStatusInMenuBar = true
    XCTAssertEqual(model.selectedActivityState, .finished)
    grokMonitor.stateOnRefresh = .running
    model.setDisplayMode(.grok)
    XCTAssertEqual(model.selectedActivityState, .running)
  }

  @MainActor
  func testTaskMonitoringPreferencePersists() throws {
    let suite = "TaskMonitoringTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    XCTAssertFalse(model.showTaskStatusInMenuBar)
    model.showTaskStatusInMenuBar = true
    let restored = AppModel(defaults: defaults)
    XCTAssertTrue(restored.showTaskStatusInMenuBar)
  }

  func testTaskTrafficLightStateMapping() {
    for mode in DisplayMode.allCases where mode.isUsageMode {
      XCTAssertEqual(TaskTrafficLight.activeIndex(state: .idle, mode: mode), 2)
      XCTAssertEqual(TaskTrafficLight.activeIndex(state: .running, mode: mode), 1)
      XCTAssertEqual(TaskTrafficLight.activeIndex(state: .finished, mode: mode), 2)
      XCTAssertEqual(TaskTrafficLight.activeIndex(state: .awaitingAuthorization, mode: mode), 0)
      XCTAssertEqual(TaskTrafficLight.activeIndex(state: .toolFailed, mode: mode), 0)
      XCTAssertNil(TaskTrafficLight.activeIndex(state: nil, mode: mode))
    }
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: .idle, mode: .grok), 2)
    XCTAssertEqual(TaskTrafficLight.activeIndex(state: .idle, mode: .codex), 2)
    XCTAssertNil(TaskTrafficLight.activeIndex(state: .running, mode: .customImage))
    XCTAssertFalse(TaskTrafficLight.makeImage(state: .running, mode: .codex).isTemplate)
    XCTAssertEqual(TaskTrafficLight.makeImage(state: .running, mode: .codex).size,
                   NSSize(width: 60, height: 18))
  }

  @MainActor
  func testSelectedTaskStatusFollowsDisplayMode() throws {
    let suite = "TaskMonitoringTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for mode in DisplayMode.allCases {
      defaults.set(mode.rawValue, forKey: "displayMode")
      let model = AppModel(defaults: defaults)
      switch mode {
      case .codex: XCTAssertEqual(model.selectedActivityState, model.codexActivityState)
      case .claudeCode: XCTAssertEqual(model.selectedActivityState, model.claudeActivityState)
      case .qoder: XCTAssertEqual(model.selectedActivityState, model.qoderActivityState)
      case .grok: XCTAssertEqual(model.selectedActivityState, model.grokActivityState)
      case .customImage: XCTAssertNil(model.selectedActivityState)
      }
    }
  }

  @MainActor
  func testSettingsWindowPresenterRecognizesChineseAndEnglishTitles() {
    let chineseWindow = NSWindow()
    chineseWindow.title = "“AI 监视器”设置"

    let englishWindow = NSWindow()
    englishWindow.title = "AI Monitor Settings"

    let unrelatedWindow = NSWindow()
    unrelatedWindow.title = "软件更新"

    XCTAssertTrue(SettingsWindowPresenter.isSettingsWindow(chineseWindow))
    XCTAssertTrue(SettingsWindowPresenter.isSettingsWindow(englishWindow))
    XCTAssertFalse(SettingsWindowPresenter.isSettingsWindow(unrelatedWindow))
  }

  @MainActor
  func testUsageCardAppearancePersistsAndUpdatesPreview() throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(defaults: defaults)
    let originalPreview = try XCTUnwrap(model.previewImage?.tiffRepresentation)

    model.setUsageCardColorScheme(.cloudDancer)

    XCTAssertEqual(model.usageCardColorScheme, .cloudDancer)
    XCTAssertEqual(
      defaults.string(forKey: "usageCardColorScheme"),
      UsageCardColorScheme.cloudDancer.rawValue
    )
    XCTAssertNotEqual(model.previewImage?.tiffRepresentation, originalPreview)

    let colorPreview = try XCTUnwrap(model.previewImage?.tiffRepresentation)
    model.setUsageCardDesign(.orbitalRings)

    XCTAssertEqual(model.usageCardDesign, .orbitalRings)
    XCTAssertEqual(
      defaults.string(forKey: "usageCardDesign"),
      UsageCardDesign.orbitalRings.rawValue
    )
    XCTAssertNotEqual(model.previewImage?.tiffRepresentation, colorPreview)

    let restoredModel = AppModel(defaults: defaults)
    XCTAssertEqual(restoredModel.usageCardColorScheme, .cloudDancer)
    XCTAssertEqual(restoredModel.usageCardDesign, .orbitalRings)
  }

  @MainActor
  func testLegacyStylePreferenceMigratesToColorScheme() throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(UsageCardColorScheme.signalYellow.rawValue, forKey: "usageCardStyle")
    let model = AppModel(defaults: defaults)

    XCTAssertEqual(model.usageCardColorScheme, .signalYellow)
    XCTAssertEqual(model.usageCardDesign, .classic)
  }

  @MainActor
  func testCustomImageModePausesCodexAndSwitchingBackRefreshesImmediately() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let codexClient = FakeCodexClient()
    let imageClient = FakeImageClient()
    let activityMonitor = FakeCodexActivityMonitor()
    let imageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: imageDirectory) }
    let model = AppModel(
      defaults: defaults,
      codexClient: codexClient,
      imageAPIClient: imageClient,
      activityMonitor: activityMonitor,
      customImageDirectory: imageDirectory
    )

    model.start()
    let initialSyncCompleted = await waitUntil {
      let fetchCount = await codexClient.fetchCount
      let uploadCount = await imageClient.uploadCount
      return fetchCount == 1 && uploadCount == 1
    }
    XCTAssertTrue(initialSyncCompleted)
    XCTAssertEqual(model.keyboardConnectionState, .connected)
    XCTAssertEqual(model.usageQueryState, .succeeded)

    let imageURL = try makeTemporaryImage()
    defer { try? FileManager.default.removeItem(at: imageURL) }
    model.selectCustomImage(at: imageURL)

    let customUploadCompleted = await waitUntil {
      await imageClient.uploadCount == 2
    }
    XCTAssertTrue(customUploadCompleted)
    XCTAssertEqual(model.displayMode, .customImage)
    XCTAssertEqual(model.usageQueryState, .idle)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: imageDirectory.appendingPathComponent("custom-image.png").path))

    model.refreshOnly()
    try await Task.sleep(nanoseconds: 100_000_000)
    let pausedFetchCount = await codexClient.fetchCount
    XCTAssertEqual(pausedFetchCount, 1)

    model.setDisplayMode(.codex)
    let codexResumeCompleted = await waitUntil {
      let fetchCount = await codexClient.fetchCount
      let uploadCount = await imageClient.uploadCount
      return fetchCount == 2 && uploadCount == 3
    }
    XCTAssertTrue(codexResumeCompleted)
    XCTAssertEqual(model.displayMode, .codex)
    XCTAssertEqual(model.keyboardConnectionState, .connected)
    XCTAssertEqual(model.usageQueryState, .succeeded)

    model.endpoint = "http://192.168.31.72/image/upload"
    XCTAssertEqual(model.keyboardConnectionState, .disconnected)
  }

  @MainActor
  func testFailedUsageQueryUpdatesMenuBarState() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(
      defaults: defaults,
      codexClient: FailingCodexClient(),
      imageAPIClient: FakeImageClient()
    )

    await model.synchronize(upload: false, forceUpload: false)

    XCTAssertEqual(model.usageQueryState, .failed)
    XCTAssertNotNil(model.lastError)
    XCTAssertEqual(model.keyboardConnectionState, .disconnected)
  }

  @MainActor
  func testActivityChangeImmediatelyRendersAndPushesTrafficLight() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(UsageCardDesign.minimalColumn.rawValue, forKey: "usageCardDesign")

    let activityMonitor = FakeCodexActivityMonitor()
    let imageClient = FakeImageClient()
    let hookRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("app-model-hook-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: hookRoot) }
    let hookInstaller = CodexHookInstaller(
      configURL: hookRoot.appendingPathComponent(".codex/hooks.json"),
      handlerURL: hookRoot.appendingPathComponent("hooks/codex-linx-activity-hook.py")
    )
    try hookInstaller.install()
    let model = AppModel(
      defaults: defaults,
      codexClient: FakeCodexClient(),
      imageAPIClient: imageClient,
      activityMonitor: activityMonitor,
      hookInstaller: hookInstaller
    )

    model.start()
    let initialUploadCompleted = await waitUntil {
      await imageClient.uploadCount == 1
    }
    XCTAssertTrue(initialUploadCompleted)

    activityMonitor.send(.running)

    let activityUploadCompleted = await waitUntil {
      await imageClient.uploadCount == 2
    }
    XCTAssertTrue(activityUploadCompleted)
    XCTAssertEqual(model.codexActivityState, .running)
    XCTAssertEqual(model.codexActivityState.title, "任务进行中")
    guard case .active = model.codexHookInstallationState else {
      return XCTFail("收到真实事件后 Hook 应标记为已生效")
    }
    XCTAssertTrue(model.codexHookStatusText.hasPrefix("已生效"))
  }

  @MainActor
  func testReachableKeyboardWithRejectedPushShowsDimmedLogo() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(
      defaults: defaults,
      codexClient: FakeCodexClient(),
      imageAPIClient: RejectingImageClient()
    )

    await model.synchronize(upload: true, forceUpload: true)

    XCTAssertEqual(model.keyboardConnectionState, .pushFailed)
    XCTAssertEqual(MenuBarIconAppearance.logoOpacity(for: .pushFailed), 0.5)
  }

  @MainActor
  func testUnreachableKeyboardHidesLogo() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(
      defaults: defaults,
      codexClient: FakeCodexClient(),
      imageAPIClient: DisconnectedImageClient()
    )

    await model.synchronize(upload: true, forceUpload: true)

    XCTAssertEqual(model.keyboardConnectionState, .disconnected)
    XCTAssertEqual(MenuBarIconAppearance.logoOpacity(for: .disconnected), 0)
  }

  @MainActor
  private func makeTemporaryImage() throws -> URL {
    let image = NSImage(size: NSSize(width: 320, height: 180))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 320, height: 180).fill()
    image.unlockFocus()

    let tiffData = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
    let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-linx-test-\(UUID().uuidString).png")
    try pngData.write(to: url, options: .atomic)
    return url
  }

  private func waitUntil(
    _ condition: @escaping () async -> Bool
  ) async -> Bool {
    for _ in 0..<100 {
      if await condition() { return true }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
  }
}

final class MenuBarStatusIconTests: XCTestCase {
  @MainActor
  func testEveryDisplayModeUsesDistinctMonochromeTemplateIcon() throws {
    let images = DisplayMode.allCases.map { mode in
      MenuBarStatusIcon.makeStatusImage(
        connectionState: .connected,
        displayMode: mode
      )
    }

    XCTAssertTrue(images.allSatisfy(\.isTemplate))
    XCTAssertEqual(Set(try images.map { try XCTUnwrap($0.tiffRepresentation) }).count, images.count)

    for image in images {
      let bitmap = try bitmap(for: image)
      var visibleCenterPixelCount = 0
      var coloredPixelCount = 0

      for x in 3..<15 {
        for y in 3..<15 {
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            color.alphaComponent > 0.1
          else { continue }
          visibleCenterPixelCount += 1
          let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
          let minimum = min(color.redComponent, color.greenComponent, color.blueComponent)
          if maximum - minimum > 0.02 { coloredPixelCount += 1 }
        }
      }

      XCTAssertGreaterThan(visibleCenterPixelCount, 8)
      XCTAssertEqual(coloredPixelCount, 0)
    }
  }

  @MainActor
  func testLogoIsMonochromeTemplateWithTransparentTerminalMark() throws {
    let image = MenuBarStatusIcon.makeLogoImage()
    let bitmap = try bitmap(for: image)
    var visiblePixelCount = 0
    var coloredPixelCount = 0
    var transparentPromptPixelCount = 0

    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
          continue
        }
        if color.alphaComponent > 0.1 {
          visiblePixelCount += 1
          let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
          let minimum = min(color.redComponent, color.greenComponent, color.blueComponent)
          if maximum - minimum > 0.02 {
            coloredPixelCount += 1
          }
        }
        if x >= 5, x <= 13, y >= 7, y <= 11,
          color.alphaComponent < 0.25
        {
          transparentPromptPixelCount += 1
        }
      }
    }

    XCTAssertGreaterThan(visiblePixelCount, 20)
    XCTAssertEqual(coloredPixelCount, 0)
    XCTAssertGreaterThan(transparentPromptPixelCount, 2)
    XCTAssertTrue(image.isTemplate)
  }

  @MainActor
  func testFrameContainsNoColoredPixels() throws {
    let bitmap = try bitmap(
      for: MenuBarStatusIcon.makeFrameImage()
    )
    var saturatedPixelCount = 0
    var visiblePixelCount = 0

    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
          continue
        }
        let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
        let minimum = min(color.redComponent, color.greenComponent, color.blueComponent)
        if maximum - minimum > 0.1, color.alphaComponent > 0.1 {
          saturatedPixelCount += 1
        }
        if color.alphaComponent > 0.1 {
          visiblePixelCount += 1
        }
      }
    }

    XCTAssertEqual(saturatedPixelCount, 0)
    XCTAssertGreaterThan(visiblePixelCount, 20)
  }

  @MainActor
  func testDisconnectedStatusImageStillContainsFrame() throws {
    let bitmap = try bitmap(
      for: MenuBarStatusIcon.makeStatusImage(
        connectionState: .disconnected
      )
    )
    var visibleBorderPixelCount = 0
    var visibleCenterPixelCount = 0

    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        guard color.alphaComponent > 0.1 else { continue }
        if x <= 2 || x >= 15 || y <= 2 || y >= 15 {
          visibleBorderPixelCount += 1
        } else if x >= 5, x <= 13, y >= 5, y <= 13 {
          visibleCenterPixelCount += 1
        }
      }
    }

    XCTAssertGreaterThan(visibleBorderPixelCount, 20)
    XCTAssertEqual(visibleCenterPixelCount, 0)
  }

  func testKeyboardPushAppearanceRules() {
    XCTAssertEqual(MenuBarIconAppearance.logoOpacity(for: .disconnected), 0)
    XCTAssertEqual(MenuBarIconAppearance.logoOpacity(for: .connected), 1)
    XCTAssertEqual(MenuBarIconAppearance.logoOpacity(for: .pushFailed), 0.5)
  }

  @MainActor
  private func bitmap(for image: NSImage) throws -> NSBitmapImageRep {
    let data = try XCTUnwrap(image.tiffRepresentation)
    return try XCTUnwrap(NSBitmapImageRep(data: data))
  }
}

@MainActor
private final class FakeCodexActivityMonitor: CodexActivityMonitoring {
  var stateOnRefresh: CodexActivityState?
  private(set) var state: CodexActivityState = .idle
  private(set) var lastEventDate: Date?
  var onStateChange: ((CodexActivityState) -> Void)?
  var onEventObserved: ((Date) -> Void)?

  private(set) var isStarted = false
  func start() { isStarted = true }
  func stop() { isStarted = false }
  func refresh() {
    if let stateOnRefresh { state = stateOnRefresh }
  }

  func send(_ state: CodexActivityState) {
    self.state = state
    let date = Date()
    lastEventDate = date
    onEventObserved?(date)
    onStateChange?(state)
  }
}

private actor FakeCodexClient: CodexRateLimitFetching {
  private(set) var fetchCount = 0

  func fetch() async throws -> UsageSnapshot {
    fetchCount += 1
    return .sample
  }
}

private actor FailingCodexClient: CodexRateLimitFetching {
  func fetch() async throws -> UsageSnapshot {
    throw TestError.queryFailed
  }
}

private actor RejectingImageClient: ImageUploading {
  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    throw ImageAPIError.rejected(500, "测试推送失败")
  }
}

private actor DisconnectedImageClient: ImageUploading {
  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    throw ImageAPIError.connectionFailed
  }
}

private enum TestError: LocalizedError {
  case queryFailed

  var errorDescription: String? { "测试查询失败" }
}

private actor FakeImageClient: ImageUploading {
  private(set) var uploadCount = 0

  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    uploadCount += 1
    return ImageUploadResult(statusCode: 200, responseText: "OK")
  }
}
