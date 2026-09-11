import AppKit
import SwiftUI

@main
@MainActor
struct CodexLinxDisplayApp: App {
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
      MenuBarContentView(
        model: model,
        checkForUpdates: updater.checkForUpdates
      )
    } label: {
      MenuBarStatusLabel(
        title: menuBarTitle,
        connectionState: model.keyboardConnectionState,
        displayMode: model.displayMode,
        showTaskStatus: model.showTaskStatusInMenuBar,
        iconPosition: model.menuBarOriginalIconPosition,
        activityState: model.selectedActivityState
      )
      .task { model.start() }
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(
        model: model,
        checkForUpdates: updater.checkForUpdates
      )
        .task { model.start() }
    }
    .windowResizability(.contentSize)
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
  let iconPosition: MenuBarOriginalIconPosition
  let activityState: CodexActivityState?

  var body: some View {
    Image(
      nsImage: MenuBarStatusIcon.makeCombinedImage(
        connectionState: connectionState,
        displayMode: displayMode,
        showTaskStatus: showTaskStatus,
        activityState: activityState,
        iconPosition: iconPosition,
        darkAppearance: colorScheme == .dark
      )
    )
      .renderingMode(showTaskStatus ? .original : .template)
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
    return "\(title)，\(stateText)\(taskText)"
  }
}

enum MenuBarIconAppearance {
  static func logoOpacity(for state: KeyboardConnectionState) -> Double {
    switch state {
    case .disconnected: return 0
    case .connected: return 1
    case .pushFailed: return 0.5
    }
  }
}

enum MenuBarStatusIcon {
  private static let imageSize = NSSize(width: 18, height: 18)

  // MenuBarExtra bridges its label to an NSStatusItem; use one image rather
  // than multiple Image children, which can be dropped by that bridge.
  static func makeCombinedImage(
    connectionState: KeyboardConnectionState,
    displayMode: DisplayMode,
    showTaskStatus: Bool,
    activityState: CodexActivityState?,
    iconPosition: MenuBarOriginalIconPosition = .left,
    darkAppearance: Bool = false
  ) -> NSImage {
    let icon = makeStatusImage(connectionState: connectionState, displayMode: displayMode)
    guard showTaskStatus else { return icon }
    let lights = TaskTrafficLight.makeImage(state: activityState, mode: displayMode)
    guard iconPosition != .hidden else { return lights }
    let iconX: CGFloat = iconPosition == .left ? 0 : lights.size.width + 12
    let lightsX: CGFloat = iconPosition == .left ? 30 : 0
    let image = NSImage(size: NSSize(width: 30 + lights.size.width, height: 18), flipped: false) { _ in
      let iconRect = NSRect(x: iconX, y: 0, width: imageSize.width, height: imageSize.height)
      icon.draw(in: iconRect)
      (darkAppearance ? NSColor.white : NSColor.black).setFill()
      iconRect.fill(using: .sourceAtop)
      lights.draw(in: NSRect(x: lightsX, y: 0, width: lights.size.width, height: 18))
      return true
    }
    image.isTemplate = false
    return image
  }

  static func makeStatusImage(
    connectionState: KeyboardConnectionState,
    displayMode: DisplayMode = .codex
  ) -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      let logoOpacity = MenuBarIconAppearance.logoOpacity(for: connectionState)
      if logoOpacity > 0 {
        drawLogo(for: displayMode, opacity: logoOpacity)
      }
      drawFrame()
      return true
    }
    image.isTemplate = true
    return image
  }

  static func makeFrameImage() -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      drawFrame()
      return true
    }
    image.isTemplate = true
    return image
  }

  static func makeLogoImage(displayMode: DisplayMode = .codex) -> NSImage {
    let image = NSImage(size: imageSize, flipped: false) { _ in
      drawLogo(for: displayMode, opacity: 1)
      return true
    }
    image.isTemplate = true
    return image
  }

  private static func drawFrame() {
    NSColor.black.withAlphaComponent(0.82).setStroke()

    let frame = NSBezierPath(
      roundedRect: NSRect(x: 0.75, y: 0.75, width: 16.5, height: 16.5),
      xRadius: 3.2,
      yRadius: 3.2
    )
    frame.lineWidth = 1.1
    frame.stroke()
  }

  private static func drawLogo(for displayMode: DisplayMode, opacity: Double) {
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
