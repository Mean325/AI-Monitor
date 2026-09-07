import AppKit
import SwiftUI

/// A consistent material layer that doesn't change into inactive-window gray.
struct AppFrostedBackdrop: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .sidebar
  var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = ClippedVisualEffectView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    view.isEmphasized = false
    view.wantsLayer = true
    view.layer?.masksToBounds = true
  }
}

private final class ClippedVisualEffectView: NSVisualEffectView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  override func layout() {
    super.layout()
    layer?.masksToBounds = true
  }
}

struct AppGlassPanel: ViewModifier {
  var tint: Color = .teal
  var radius: CGFloat = 20
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    content
      .background {
        ZStack {
          if reduceTransparency {
            shape.fill(scheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.18) : .white)
          } else {
            AppFrostedBackdrop(material: .contentBackground)
            shape.fill(scheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.42))
          }
          shape.fill(LinearGradient(
            colors: [tint.opacity(scheme == .dark ? 0.1 : 0.065), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .clipShape(shape)
        .compositingGroup()
      }
      .overlay {
        shape.strokeBorder(LinearGradient(
          colors: [Color.white.opacity(scheme == .dark ? 0.22 : 0.85), tint.opacity(0.12), Color.white.opacity(0.06)],
          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
          .allowsHitTesting(false)
        if contrast == .increased {
          shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
            .allowsHitTesting(false)
        }
      }
      .shadow(color: .black.opacity(scheme == .dark ? 0.13 : 0.045), radius: 12, y: 5)
  }
}

struct AppGlassButton: ViewModifier {
  var prominent = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      if prominent { content.buttonStyle(.glassProminent) }
      else { content.buttonStyle(.glass) }
    } else {
      if prominent { content.buttonStyle(.borderedProminent) }
      else { content.buttonStyle(.bordered) }
    }
  }
}

struct AppGlassGroup<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @ViewBuilder var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 12) { content() }
    } else { content() }
  }
}

struct OverlayScrollChrome: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(.clear)
      .background(OverlayScrollChromeInstaller())
  }
}

struct OverlayScrollChromeInstaller: NSViewRepresentable {
  func makeNSView(context: Context) -> OverlayScrollChromeView {
    OverlayScrollChromeView()
  }

  func updateNSView(_ view: OverlayScrollChromeView, context: Context) {
    view.applyChrome()
  }
}

final class OverlayScrollChromeView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = NSUserInterfaceItemIdentifier("OverlayScrollChromeInstaller")
    isHidden = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    isHidden = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyChrome()
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    applyChrome()
  }

  override func layout() {
    super.layout()
    applyChrome()
  }

  func applyChrome() {
    guard let scrollView = nearestScrollView() else { return }
    scrollView.drawsBackground = false
    scrollView.backgroundColor = .clear
    scrollView.contentView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.scrollerStyle = .overlay
    scrollView.autohidesScrollers = true
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.scrollerKnobStyle = .default
    scrollView.verticalScroller?.controlSize = .mini
    scrollView.verticalScroller?.knobStyle = .default
    scrollView.verticalScroller?.alphaValue = 0.32
    scrollView.horizontalScroller?.alphaValue = 0
  }

  private func nearestScrollView() -> NSScrollView? {
    var current: NSView? = self
    for _ in 0..<20 {
      guard let node = current else { break }
      if let scrollView = node as? NSScrollView { return scrollView }
      if let scrollView = node.enclosingScrollView { return scrollView }
      if let scrollView = node.subviews.compactMap({ $0 as? NSScrollView }).first {
        return scrollView
      }
      current = node.superview
    }
    return enclosingScrollView
  }
}

extension View {
  func overlayScrollChrome() -> some View {
    modifier(OverlayScrollChrome())
  }
}
