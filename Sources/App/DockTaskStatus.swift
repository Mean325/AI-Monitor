import AppKit
import Combine

/// A single status light on a plain background, sized for the macOS Dock.
enum DockTaskStatusIcon {
  static func makeImage(state: CodexActivityState?, darkAppearance: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { _ in
      // Custom Dock tiles do not receive the system app-icon shadow; include
      // it in the shared artwork so preview and Dock retain the same depth.
      NSGraphicsContext.saveGraphicsState()
      let tileShadow = NSShadow()
      tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
      tileShadow.shadowOffset = NSSize(width: 0, height: -8)
      tileShadow.shadowBlurRadius = 16
      tileShadow.set()
      (darkAppearance ? NSColor.black : NSColor.white).setFill()
      NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 448, height: 448),
                   xRadius: 100, yRadius: 100).fill()
      NSGraphicsContext.restoreGraphicsState()
      let color: NSColor
      switch state {
      case .awaitingAuthorization, .toolFailed, .quotaExhausted:
        color = NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)
      case .running:
        color = NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1)
      case .idle, .finished:
        color = NSColor(srgbRed: 0.16, green: 0.79, blue: 0.26, alpha: 1)
      case nil:
        color = .systemGray
      }
      // Scale the complete light around its center, including its bevels.
      NSGraphicsContext.saveGraphicsState()
      let lightTransform = NSAffineTransform()
      lightTransform.translateX(by: 256, yBy: 256)
      lightTransform.scale(by: 0.9)
      lightTransform.translateX(by: -256, yBy: -256)
      lightTransform.concat()

      // A thick, beveled black housing with light coming from above.
      let housing = NSBezierPath(ovalIn: NSRect(x: 64, y: 64, width: 384, height: 384))
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
      shadow.shadowOffset = NSSize(width: 0, height: -9)
      shadow.shadowBlurRadius = 16
      shadow.set()
      NSColor.black.setFill()
      housing.fill()
      NSGraphicsContext.restoreGraphicsState()

      // Gloss-black enamel: a broad overhead reflection rolls into the
      // dark sides, with a restrained bounce from below.
      NSGradient(colorsAndLocations:
        (NSColor(white: 0.10, alpha: 1), 0),
        (NSColor(white: 0.025, alpha: 1), 0.18),
        (NSColor(white: 0.035, alpha: 1), 0.48),
        (NSColor(white: 0.15, alpha: 1), 0.74),
        (NSColor(white: 0.34, alpha: 1), 0.92),
        (NSColor(white: 0.19, alpha: 1), 1)
      )?.draw(in: housing, angle: 90)

      NSGraphicsContext.saveGraphicsState()
      housing.addClip()
      let enamelReflection = NSPoint(x: 180, y: 433)
      NSGradient(starting: NSColor.white.withAlphaComponent(0.32),
                 ending: NSColor.white.withAlphaComponent(0))?
        .draw(fromCenter: enamelReflection, radius: 0,
              toCenter: enamelReflection, radius: 155, options: [])
      NSGraphicsContext.restoreGraphicsState()

      // Continuous highlights describe the rolled outer lip without
      // drawing conspicuous white stripes across the black housing.
      let outerLip = NSBezierPath(ovalIn: NSRect(x: 66, y: 66, width: 380, height: 380))
      outerLip.appendOval(in: NSRect(x: 69, y: 69, width: 374, height: 374))
      outerLip.windingRule = .evenOdd
      NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.22), 0),
        (NSColor.white.withAlphaComponent(0.02), 0.32),
        (NSColor.white.withAlphaComponent(0.06), 0.68),
        (NSColor.white.withAlphaComponent(0.60), 1)
      )?.draw(in: outerLip, angle: 90)
      NSColor.black.withAlphaComponent(0.85).setStroke()
      housing.lineWidth = 1.5
      housing.stroke()

      // The deep inner bevel catches light below and shades the lens above,
      // like the recessed glass in a real signal lamp.
      let innerRim = NSBezierPath(ovalIn: NSRect(x: 98, y: 98, width: 316, height: 316))
      NSGradient(colorsAndLocations:
        (NSColor(white: 0.34, alpha: 1), 0),
        (NSColor(white: 0.11, alpha: 1), 0.22),
        (NSColor(white: 0.018, alpha: 1), 0.58),
        (NSColor.black, 1)
      )?.draw(in: innerRim, angle: 90)
      let lens = NSBezierPath(ovalIn: NSRect(x: 108, y: 108, width: 296, height: 296))
      // Window-control glass has a saturated, shaded upper edge and a
      // luminous lower rim. Keep reflections continuous, without painted
      // white arcs, so the lens still reads as glass at small Dock sizes.
      let glassTop = color.blended(withFraction: 0.24, of: .black) ?? color
      let glassBody = color.blended(withFraction: 0.10, of: .white) ?? color
      let glassBottom = color.blended(withFraction: 0.32, of: .white) ?? color
      NSGradient(colorsAndLocations:
        (glassBottom, 0), (glassBody, 0.16), (color, 0.52),
        (glassTop, 0.92), (glassTop, 1)
      )?.draw(in: lens, angle: 90)

      NSGraphicsContext.saveGraphicsState()
      lens.addClip()

      // Broad diffused reflection rather than a glossy plastic hotspot.
      let reflectionCenter = NSPoint(x: 230, y: 310)
      NSGradient(starting: NSColor.white.withAlphaComponent(0.24),
                 ending: NSColor.white.withAlphaComponent(0))?
        .draw(fromCenter: reflectionCenter, radius: 0,
              toCenter: reflectionCenter, radius: 180, options: [])

      // Light refracts through the curved perimeter. The transparent middle
      // preserves the status hue and the lower edge catches the most light.
      let center = NSPoint(x: 256, y: 256)
      NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0), 0),
        (NSColor.black.withAlphaComponent(0), 0.86),
        (NSColor.black.withAlphaComponent(0.07), 0.96),
        (NSColor.black.withAlphaComponent(0.24), 1)
      )?.draw(fromCenter: center, radius: 0,
              toCenter: center, radius: 148, options: [])

      let lowerGlow = NSPoint(x: 256, y: 105)
      NSGradient(starting: NSColor.white.withAlphaComponent(0.38),
                 ending: NSColor.white.withAlphaComponent(0))?
        .draw(fromCenter: lowerGlow, radius: 0,
              toCenter: lowerGlow, radius: 115, options: [])

      // A thin annular highlight follows the full curvature; a vertical
      // gradient fades the sides naturally instead of ending in round caps.
      let edge = NSBezierPath(ovalIn: NSRect(x: 110, y: 110, width: 292, height: 292))
      edge.appendOval(in: NSRect(x: 113, y: 113, width: 286, height: 286))
      edge.windingRule = .evenOdd
      NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.78), 0),
        (NSColor.white.withAlphaComponent(0.28), 0.12),
        (NSColor.white.withAlphaComponent(0.04), 0.42),
        (NSColor.white.withAlphaComponent(0.05), 0.72),
        (NSColor.white.withAlphaComponent(0.42), 1)
      )?.draw(in: edge, angle: 90)
      NSGraphicsContext.restoreGraphicsState()
      NSColor.black.withAlphaComponent(0.22).setStroke()
      lens.lineWidth = 1.5
      lens.stroke()

      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    // Materialize the artwork at its full resolution before handing it to
    // SwiftUI or the Dock. Both surfaces use the same baked gradients/shadows.
    let rendered = image.tiffRepresentation.flatMap { NSImage(data: $0) } ?? image
    rendered.size = image.size
    rendered.isTemplate = false
    rendered.accessibilityDescription = state?.title ?? "未选择 AI"
    return rendered
  }
}

@MainActor
final class DockTaskStatusController {
  private struct Presentation: Equatable {
    let enabled: Bool
    let state: CodexActivityState?
    let darkAppearance: Bool
  }

  private weak var model: AppModel?
  private var subscription: AnyCancellable?
  private var appearanceObservation: NSKeyValueObservation?
  private var originalIcon: NSImage?
  private let dockImageView = NSImageView()
  private var lastPresentation: Presentation?

  init(model: AppModel) { self.model = model }

  func start() {
    guard subscription == nil,
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    originalIcon = NSApp.applicationIconImage
    dockImageView.imageScaling = .scaleProportionallyUpOrDown
    // Published values are delivered before mutation, so read the model on
    // the next main-queue pass, after display and activity changes settle.
    subscription = model?.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.refresh() }
    }
    appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async { self?.refresh() }
    }
    refresh()
  }

  private func refresh() {
    guard let model else { return }
    let presentation = Presentation(
      enabled: model.showTaskStatusInDock,
      state: model.selectedActivityState,
      darkAppearance: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    )
    guard presentation != lastPresentation else { return }
    if lastPresentation?.enabled != presentation.enabled {
      NSApp.setActivationPolicy(presentation.enabled ? .regular : .accessory)
    }
    if presentation.enabled {
      let image = DockTaskStatusIcon.makeImage(
        state: presentation.state, darkAppearance: presentation.darkAppearance)
      NSApp.applicationIconImage = image
      // Draw the exact preview artwork into the tile, bypassing automatic
      // application-icon styling and cached Dock icon representations.
      dockImageView.frame = NSRect(origin: .zero, size: NSApp.dockTile.size)
      dockImageView.image = image
      NSApp.dockTile.contentView = dockImageView
      NSApp.dockTile.display()
    } else if lastPresentation?.enabled == true {
      NSApp.dockTile.contentView = nil
      dockImageView.image = nil
      NSApp.applicationIconImage = originalIcon
      NSApp.dockTile.display()
    }
    lastPresentation = presentation
  }
}

extension Notification.Name {
  static let dockTaskStatusOpenSettings = Notification.Name("DockTaskStatusOpenSettings")
}

@MainActor
final class DockTaskStatusAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    NotificationCenter.default.post(name: .dockTaskStatusOpenSettings, object: nil)
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
