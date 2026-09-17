import AppKit
import SwiftUI

@main
@MainActor
struct CodexLinxDisplayApp: App {
  @Environment(\.openSettings) private var openSettings
  @StateObject private var model: AppModel
  private let updater: UpdaterController

  init() {
    let hookInstaller = CodexHookInstaller()
    let claudeHookInstaller = ClaudeCodeHookInstaller()
    updater = UpdaterController()
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
      if hookInstaller.installationState() != .configured {
        try? hookInstaller.install()
      }
      if claudeHookInstaller.installationState() != .configured {
        try? claudeHookInstaller.install()
      }
    }

    _model = StateObject(
      wrappedValue: AppModel(
        hookInstaller: hookInstaller,
        claudeHookInstaller: claudeHookInstaller
      )
    )
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: model)
    } label: {
      MenuBarStatusLabel(
        title: menuBarTitle,
        connectionState: model.keyboardConnectionState,
        displayMode: model.presentedAIMode,
        showTaskStatus: model.showTaskStatusInMenuBar,
        showUsage: model.showUsageInMenuBar,
        remainingPercent: model.selectedUsageRemainingPercent,
        iconPosition: model.menuBarOriginalIconPosition,
        activityState: model.selectedActivityState
      )
      .task {
        model.start()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
          SettingsWindowPresenter.show(using: openSettings)
        }
        #endif
      }
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(
        model: model,
        checkForUpdates: updater.checkForUpdates
      )
        .task { model.start() }
    }
    .windowResizability(.automatic)
  }

  private var menuBarTitle: String {
    if model.displayMode == .customImage {
      return "图片显示"
    }
    if model.displayMode == .claudeCode {
      if let snapshot = model.claudeSnapshot, snapshot.hasData {
        return "CC \(ClaudeCodeTokenFormatter.string(from: snapshot.todayTokens))"
      }
      return "Claude Code"
    }
    if model.displayMode == .qoder {
      if let credit = model.qoderCreditSnapshot, credit.hasData {
        return "Qoder \(credit.creditsPercentageDisplay)"
      }
      return "Qoder"
    }
    if model.displayMode == .grok {
      if let snapshot = model.grokSnapshot {
        return "Grok \(snapshot.remainingPercent)%"
      }
      return "Grok"
    }
    if let snapshot = model.snapshot {
      return "Codex \(snapshot.remainingPercent)%"
    }
    return AppBrand.displayName
  }
}

private struct MenuBarStatusLabel: View {
  @Environment(\.colorScheme) private var colorScheme
  let title: String
  let connectionState: KeyboardConnectionState
  let displayMode: DisplayMode
  let showTaskStatus: Bool
  let showUsage: Bool
  let remainingPercent: Int?
  let iconPosition: MenuBarOriginalIconPosition
  let activityState: CodexActivityState?

  var body: some View {
    Image(
      nsImage: MenuBarStatusIcon.makeCombinedImage(
        connectionState: connectionState,
        displayMode: displayMode,
        showTaskStatus: showTaskStatus,
        showUsage: showUsage,
        remainingPercent: remainingPercent,
        activityState: activityState,
        iconPosition: iconPosition,
        darkAppearance: colorScheme == .dark
      )
    )
      .renderingMode(.original)
      .accessibilityLabel(Text(accessibilityText))
  }

  private var accessibilityText: String {
    let stateText: String
    switch connectionState {
    case .disconnected: stateText = "键盘未连接"
    case .connected: stateText = "键盘推送成功"
    case .pushFailed: stateText = "键盘已连接，但推送失败"
    }
    let taskText = showTaskStatus ? "，\(activityState?.title ?? "未选择 AI")" : ""
    let usageText = showUsage ? "，剩余用量 \(remainingPercent.map(String.init) ?? "未知")%" : ""
    return "\(title)，\(stateText)\(usageText)\(taskText)"
  }
}

enum MenuBarIconAppearance {
  static func activePushDotCount(for state: KeyboardConnectionState) -> Int {
    switch state {
    case .disconnected: return 0
    case .pushFailed: return 1
    case .connected: return 3
    }
  }
}

enum MenuBarStatusIcon {
  private static let imageSize = NSSize(width: 22, height: 22)
  private static let ringCenter = NSPoint(x: 11, y: 10.35)
  private static let ringRadius: CGFloat = 8.7

  // MenuBarExtra bridges its label to an NSStatusItem; use one image rather
  // than multiple Image children, which can be dropped by that bridge.
  static func makeCombinedImage(
    connectionState: KeyboardConnectionState,
    displayMode: DisplayMode,
    showTaskStatus: Bool,
    showUsage: Bool = true,
    remainingPercent: Int? = nil,
    activityState: CodexActivityState?,
    iconPosition: MenuBarOriginalIconPosition = .left,
    darkAppearance: Bool = false
  ) -> NSImage {
    let icon = makeStatusImage(
      connectionState: connectionState,
      displayMode: displayMode,
      showUsage: showUsage,
      remainingPercent: remainingPercent,
      darkAppearance: darkAppearance
    )
    guard showTaskStatus else { return icon }
    let lights = TaskTrafficLight.makeImage(state: activityState, mode: displayMode)
    guard iconPosition != .hidden else { return lights }
    let iconX: CGFloat = iconPosition == .left ? 0 : lights.size.width + 12
    let lightsX: CGFloat = iconPosition == .left ? imageSize.width + 12 : 0
    let image = NSImage(
      size: NSSize(width: imageSize.width + 12 + lights.size.width, height: imageSize.height),
      flipped: false
    ) { _ in
      let iconRect = NSRect(x: iconX, y: 0, width: imageSize.width, height: imageSize.height)
      icon.draw(in: iconRect)
      lights.draw(in: NSRect(
        x: lightsX,
        y: (imageSize.height - lights.size.height) / 2,
        width: lights.size.width,
        height: lights.size.height
      ))
      return true
    }
    image.isTemplate = false
    return image
  }

  static func makeStatusImage(
    connectionState: KeyboardConnectionState,
    displayMode: DisplayMode = .codex,
    showUsage: Bool = true,
    remainingPercent: Int? = nil,
    darkAppearance: Bool = false
  ) -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      let foreground = darkAppearance ? NSColor.white : NSColor.black
      let placeholder = foreground.withAlphaComponent(0.22)
      if showUsage {
        drawUsageRing(
          remainingPercent: remainingPercent,
          foreground: foreground,
          placeholder: placeholder
        )
      }
      drawLogo(for: displayMode, color: foreground)
      drawPushDots(state: connectionState, foreground: foreground, placeholder: placeholder)
      return true
    }
    image.isTemplate = false
    return image
  }

  static func makeFrameImage() -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      drawUsageRing(remainingPercent: 100, foreground: .black,
                    placeholder: NSColor.black.withAlphaComponent(0.22))
      return true
    }
    image.isTemplate = false
    return image
  }

  static func makeLogoImage(displayMode: DisplayMode = .codex) -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      drawLogo(for: displayMode, color: .black)
      return true
    }
    image.isTemplate = true
    return image
  }

  private static func drawUsageRing(
    remainingPercent: Int?,
    foreground: NSColor,
    placeholder: NSColor
  ) {
    // Leave a wide lower opening so the status dots complete the circle
    // without touching the rounded ends of the usage arc.
    let start: CGFloat = -20
    let end: CGFloat = 200
    let track = NSBezierPath()
    track.appendArc(withCenter: ringCenter, radius: ringRadius, startAngle: start, endAngle: end)
    track.lineWidth = 2
    track.lineCapStyle = .round
    placeholder.setStroke()
    track.stroke()

    guard let remainingPercent else { return }
    let value = CGFloat(max(0, min(100, remainingPercent))) / 100
    guard value > 0 else { return }
    let progress = NSBezierPath()
    progress.appendArc(
      withCenter: ringCenter,
      radius: ringRadius,
      startAngle: end,
      endAngle: end - (end - start) * value,
      clockwise: true
    )
    progress.lineWidth = 2
    progress.lineCapStyle = .round
    foreground.setStroke()
    progress.stroke()
  }

  private static func drawPushDots(
    state: KeyboardConnectionState,
    foreground: NSColor,
    placeholder: NSColor
  ) {
    let activeCount = MenuBarIconAppearance.activePushDotCount(for: state)
    let angles: [CGFloat] = [230, 270, 310]
    for (index, angle) in angles.enumerated() {
      let radians = angle * .pi / 180
      let center = NSPoint(
        x: ringCenter.x + cos(radians) * ringRadius,
        y: ringCenter.y + sin(radians) * ringRadius
      )
      (index < activeCount ? foreground : placeholder).setFill()
      NSBezierPath(ovalIn: NSRect(
        x: center.x - 1.55,
        y: center.y - 1.55,
        width: 3.1,
        height: 3.1
      )).fill()
    }
  }

  private static func drawLogo(for displayMode: DisplayMode, color: NSColor) {
    if let assetName = displayMode.logoAssetName,
       let asset = NSImage(named: NSImage.Name(assetName))
    {
      let rect = NSRect(x: 6.1, y: 6.1, width: 9.8, height: 9.8)
      asset.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
      color.setFill()
      rect.fill(using: .sourceAtop)
      return
    }

    let opacity = color.alphaComponent
    color.withAlphaComponent(opacity).setStroke()
    color.withAlphaComponent(opacity).setFill()
    switch displayMode {
    case .codex:
      drawCodexLogo(opacity: opacity)
    case .claudeCode:
      drawClaudeLogo(opacity: opacity)
    case .qoder:
      drawQoderLogo(opacity: opacity)
    case .grok:
      drawGrokLogo(opacity: opacity)
    case .customImage:
      drawImageLogo(opacity: opacity)
    }
  }

  private static func drawCodexLogo(opacity: Double) {
    let logo = terminalLogoPath
    NSColor.black.withAlphaComponent(opacity).setFill()
    logo.fill()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
    NSColor.black.setStroke()
    let prompt = NSBezierPath()
    prompt.lineWidth = 1.25
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    prompt.move(to: NSPoint(x: 5.6, y: 10.9))
    prompt.line(to: NSPoint(x: 7.8, y: 9))
    prompt.line(to: NSPoint(x: 5.6, y: 7.1))
    prompt.stroke()

    let cursor = NSBezierPath()
    cursor.lineWidth = 1.25
    cursor.lineCapStyle = .round
    cursor.move(to: NSPoint(x: 9.7, y: 7.1))
    cursor.line(to: NSPoint(x: 12.7, y: 7.1))
    cursor.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func drawClaudeLogo(opacity: Double) {
    NSColor.black.withAlphaComponent(opacity).setStroke()

    let center = NSPoint(x: 9, y: 9)
    let rays: [(NSPoint, NSPoint)] = [
      (NSPoint(x: 9, y: 4.4), NSPoint(x: 9, y: 7.1)),
      (NSPoint(x: 9, y: 10.9), NSPoint(x: 9, y: 13.6)),
      (NSPoint(x: 4.4, y: 9), NSPoint(x: 7.1, y: 9)),
      (NSPoint(x: 10.9, y: 9), NSPoint(x: 13.6, y: 9)),
      (NSPoint(x: 5.7, y: 5.7), NSPoint(x: 7.6, y: 7.6)),
      (NSPoint(x: 10.4, y: 10.4), NSPoint(x: 12.3, y: 12.3)),
      (NSPoint(x: 12.3, y: 5.7), NSPoint(x: 10.4, y: 7.6)),
      (NSPoint(x: 7.6, y: 10.4), NSPoint(x: 5.7, y: 12.3)),
    ]
    let path = NSBezierPath()
    path.lineWidth = 1.55
    path.lineCapStyle = .round
    for ray in rays {
      path.move(to: ray.0)
      path.line(to: ray.1)
    }
    path.stroke()

    NSColor.black.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)).fill()
  }

  private static func drawQoderLogo(opacity: Double) {
    NSColor.black.withAlphaComponent(opacity).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 4.4, y: 4.4, width: 9.2, height: 9.2))
    ring.lineWidth = 1.55
    ring.stroke()

    let tail = NSBezierPath()
    tail.lineWidth = 1.55
    tail.lineCapStyle = .round
    tail.move(to: NSPoint(x: 10.7, y: 10.7))
    tail.line(to: NSPoint(x: 13.6, y: 13.6))
    tail.stroke()
  }

  private static func drawGrokLogo(opacity: Double) {
    NSColor.black.withAlphaComponent(opacity).setStroke()
    let star = NSBezierPath()
    star.lineWidth = 1.45
    star.lineCapStyle = .round
    star.lineJoinStyle = .round
    star.move(to: NSPoint(x: 9, y: 4.2))
    star.line(to: NSPoint(x: 10.2, y: 7.8))
    star.line(to: NSPoint(x: 13.8, y: 9))
    star.line(to: NSPoint(x: 10.2, y: 10.2))
    star.line(to: NSPoint(x: 9, y: 13.8))
    star.line(to: NSPoint(x: 7.8, y: 10.2))
    star.line(to: NSPoint(x: 4.2, y: 9))
    star.line(to: NSPoint(x: 7.8, y: 7.8))
    star.close()
    NSColor.black.withAlphaComponent(opacity).setFill()
    star.fill()
  }

  private static func drawImageLogo(opacity: Double) {
    NSColor.black.withAlphaComponent(opacity).setStroke()

    let picture = NSBezierPath(
      roundedRect: NSRect(x: 4.2, y: 5.2, width: 9.6, height: 7.6),
      xRadius: 1.2,
      yRadius: 1.2
    )
    picture.lineWidth = 1.25
    picture.stroke()

    let mountains = NSBezierPath()
    mountains.lineWidth = 1.15
    mountains.lineCapStyle = .round
    mountains.lineJoinStyle = .round
    mountains.move(to: NSPoint(x: 5.3, y: 7))
    mountains.line(to: NSPoint(x: 7.5, y: 9.2))
    mountains.line(to: NSPoint(x: 9, y: 7.8))
    mountains.line(to: NSPoint(x: 12.7, y: 11.4))
    mountains.stroke()

    NSColor.black.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: NSRect(x: 10.7, y: 6.3, width: 1.5, height: 1.5)).fill()
  }

  private static var terminalLogoPath: NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 5.2, y: 5))
    path.curve(
      to: NSPoint(x: 3.2, y: 7.7),
      controlPoint1: NSPoint(x: 3.7, y: 5),
      controlPoint2: NSPoint(x: 2.8, y: 6.2)
    )
    path.curve(
      to: NSPoint(x: 4.1, y: 11.2),
      controlPoint1: NSPoint(x: 2.2, y: 8.8),
      controlPoint2: NSPoint(x: 2.7, y: 10.5)
    )
    path.curve(
      to: NSPoint(x: 7.3, y: 13.3),
      controlPoint1: NSPoint(x: 4, y: 13),
      controlPoint2: NSPoint(x: 5.7, y: 14.1)
    )
    path.curve(
      to: NSPoint(x: 11.4, y: 13.4),
      controlPoint1: NSPoint(x: 8.3, y: 14.8),
      controlPoint2: NSPoint(x: 10.5, y: 14.8)
    )
    path.curve(
      to: NSPoint(x: 14.8, y: 10.5),
      controlPoint1: NSPoint(x: 13.4, y: 13.8),
      controlPoint2: NSPoint(x: 15.1, y: 12.4)
    )
    path.curve(
      to: NSPoint(x: 14, y: 6.7),
      controlPoint1: NSPoint(x: 16.3, y: 9.4),
      controlPoint2: NSPoint(x: 15.7, y: 7.2)
    )
    path.curve(
      to: NSPoint(x: 10.4, y: 4.9),
      controlPoint1: NSPoint(x: 13.8, y: 4.9),
      controlPoint2: NSPoint(x: 11.8, y: 4)
    )
    path.curve(
      to: NSPoint(x: 6.2, y: 5),
      controlPoint1: NSPoint(x: 9.3, y: 3.3),
      controlPoint2: NSPoint(x: 6.8, y: 3.5)
    )
    path.curve(
      to: NSPoint(x: 5.2, y: 5),
      controlPoint1: NSPoint(x: 5.8, y: 4.9),
      controlPoint2: NSPoint(x: 5.4, y: 4.9)
    )
    path.close()
    return path
  }
}
