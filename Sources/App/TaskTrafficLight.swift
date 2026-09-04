import AppKit

/// Window-control inspired indicators, not actionable close/minimize/zoom buttons.
enum TaskTrafficLight {
  static func activeIndex(state: CodexActivityState?, mode: DisplayMode) -> Int? {
    guard mode.isUsageMode, let state else { return nil }
    switch state {
    case .awaitingAuthorization, .toolFailed: return 0
    case .running: return 1
    case .finished, .idle: return 2
    }
  }

  static func makeImage(state: CodexActivityState?, mode: DisplayMode) -> NSImage {
    let active = activeIndex(state: state, mode: mode)
    let image = NSImage(size: NSSize(width: 60, height: 18), flipped: false) { _ in
      let colors: [NSColor] = [
        NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.79, blue: 0.26, alpha: 1),
      ]
      for index in 0..<3 {
        // 14-point lights, retaining the 8-point gaps.
        let rect = NSRect(x: 1 + CGFloat(index) * 22, y: 2, width: 14, height: 14)
        let circle = NSBezierPath(ovalIn: rect)
        (active == index ? colors[index] : NSColor.gray.withAlphaComponent(0.32)).setFill()
        circle.fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        circle.lineWidth = 0.6
        circle.stroke()
      }
      return true
    }
    image.isTemplate = false
    return image
  }
}
