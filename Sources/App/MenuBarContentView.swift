import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
  @ObservedObject var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss
  @State private var menuBarWindow = MenuBarWindowReference()
  private var systemAccent: Color { Color(nsColor: .controlAccentColor) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      sectionLabel("用量概览", systemImage: "chart.bar.xaxis")
      usageSummary

      if model.isLinxEnabled {
        sectionLabel("同步状态", systemImage: "arrow.triangle.2.circlepath")

        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 7) {
              Text(model.bluetoothKeyboardInfo?.name ?? "Linx68")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

              Image(nsImage: NSImage(named: NSImage.bluetoothTemplateName) ?? NSImage())
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 11, height: 15)
                .foregroundStyle(bluetoothStatusColor)
                .accessibilityLabel(bluetoothAccessibilityText)

              HStack(spacing: 3) {
                Text(batteryPercentText)
                  .font(.caption2.monospacedDigit())
                Image(systemName: batterySymbol)
                  .font(.system(size: 13, weight: .medium))
              }
              .foregroundStyle(batteryColor)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(batteryAccessibilityText)
            }

            Spacer(minLength: 8)

            ZStack {
              if model.isSyncing {
                ProgressView()
                  .controlSize(.small)
                  .accessibilityLabel("正在同步并推送")
              } else {
                Image(systemName: pushStatusSymbol)
                  .font(.system(size: 19, weight: .bold))
                  .symbolRenderingMode(.hierarchical)
                  .foregroundStyle(pushStatusColor)
                  .accessibilityLabel(pushStatusAccessibilityText)
              }
            }
            .frame(width: 22, height: 22)
          }

          HStack {
            Text(pushTimeText)
              .font(.caption2)
              .foregroundStyle(.secondary)

            Spacer()

            Button(primarySyncActionTitle) {
              performPrimarySyncAction()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(systemAccent)
            .disabled(model.isSyncing)
          }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(AppGlassPanel(tint: .clear, radius: 14))
      }

      Divider()

      AppGlassGroup {
        HStack {
          Button {
            dismiss()
            menuBarWindow.window?.orderOut(nil)
            DispatchQueue.main.async {
              SettingsWindowPresenter.show(using: openSettings)
            }
          } label: {
            Label("设置", systemImage: "gearshape")
          }

          Spacer()

          Button("退出") {
            NSApplication.shared.terminate(nil)
          }
        }
        .modifier(AppGlassButton())
      }
    }
    .padding(16)
    .frame(width: 320)
    .background(MenuBarWindowReader(reference: menuBarWindow))
  }

  private func sectionLabel(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .padding(.top, 2)
  }

  private var primarySyncActionTitle: String {
    model.displayMode == .customImage ? "选择图片" : "刷新并推送"
  }

  private var bluetoothAccessibilityText: String {
    model.bluetoothKeyboardInfo?.isConnected == true ? "蓝牙已连接" : "蓝牙未连接"
  }

  private var bluetoothStatusColor: Color {
    model.bluetoothKeyboardInfo?.isConnected == true ? systemAccent : .secondary.opacity(0.65)
  }

  private var batterySymbol: String {
    guard model.bluetoothKeyboardInfo?.isConnected == true else {
      return "battery.0percent"
    }
    guard let battery = model.bluetoothKeyboardInfo?.batteryPercent else {
      return "battery.0percent"
    }
    switch battery {
    case 76...: return "battery.100percent"
    case 51...: return "battery.75percent"
    case 26...: return "battery.50percent"
    case 11...: return "battery.25percent"
    default: return "battery.0percent"
    }
  }

  private var batteryColor: Color {
    guard model.bluetoothKeyboardInfo?.isConnected == true else {
      return .secondary.opacity(0.65)
    }
    guard let battery = model.bluetoothKeyboardInfo?.batteryPercent else { return .secondary }
    if battery <= 10 { return .red }
    if battery <= 20 { return .orange }
    return .primary
  }

  private var batteryPercentText: String {
    guard model.bluetoothKeyboardInfo?.isConnected == true,
          let battery = model.bluetoothKeyboardInfo?.batteryPercent
    else { return "--%" }
    return "\(battery)%"
  }

  private var batteryAccessibilityText: String {
    guard model.bluetoothKeyboardInfo?.isConnected == true else { return "蓝牙未连接，电量不可用" }
    guard let battery = model.bluetoothKeyboardInfo?.batteryPercent else { return "电量不可用" }
    return "电量 \(battery)%"
  }

  private var pushTimeText: String {
    guard let date = model.lastPushRequest?.startedAt else { return "尚无推送" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd HH:mm:ss"
    return "推送于 " + formatter.string(from: date)
  }

  private var pushStatusSymbol: String {
    guard let request = model.lastPushRequest else { return "circle.dashed" }
    switch request.outcome {
    case .pending: return "clock.fill"
    case .succeeded: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    }
  }

  private var pushStatusColor: Color {
    guard let request = model.lastPushRequest else { return .secondary.opacity(0.55) }
    switch request.outcome {
    case .pending: return systemAccent.opacity(0.8)
    case .succeeded: return .green
    case .failed: return .red
    }
  }

  private var pushStatusAccessibilityText: String {
    guard let request = model.lastPushRequest else { return "尚无推送" }
    switch request.outcome {
    case .pending: return "正在推送"
    case .succeeded(let statusCode, _): return "推送成功，HTTP \(statusCode)"
    case .failed(let statusCode, _, _):
      return statusCode.map { "推送失败，HTTP \($0)" } ?? "推送失败"
    }
  }

  private func performPrimarySyncAction() {
    if model.displayMode == .customImage {
      chooseCustomImage()
    } else {
      model.pushNow()
    }
  }

  private var header: some View {
    HStack {
      BrandLogoView(mode: model.selectedAIMode, size: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(AppBrand.displayName)
          .font(.system(.headline, design: .rounded))
        Text(headerSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

    }
  }

  private var usageSummary: some View {
    Group {
      switch model.displayMode {
      case .codex:
        VStack(spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            summaryCell(
              title: model.snapshot?.windowTitle ?? "本周剩余",
              value: model.snapshot.map { "\($0.remainingPercent)%" } ?? "--",
              resetText: popupResetText(model.snapshot?.resetDate)
            )
            summaryCell(
              title: "可用重置",
              value: model.snapshot.map { "\($0.availableResetCount) 次" } ?? "--"
            )
          }
          HStack(spacing: 10) {
            summaryCell(title: "5 小时用量剩余",
              value: model.snapshot?.fiveHourRemainingPercent.map { "\($0)%" } ?? "--",
              resetText: popupResetText(model.snapshot?.fiveHourResetDate))
            Color.clear.frame(maxWidth: .infinity).frame(height: 0)
          }
        }
      case .claudeCode:
        HStack(spacing: 10) {
          summaryCell(
            title: "今日用量",
            value: model.claudeSnapshot.map {
              ClaudeCodeTokenFormatter.string(from: $0.todayTokens)
            } ?? "--"
          )
          summaryCell(
            title: "近 7 天",
            value: model.claudeSnapshot.map {
              ClaudeCodeTokenFormatter.string(from: $0.weekTokens)
            } ?? "--"
          )
        }
      case .qoder:
        HStack(spacing: 10) {
          summaryCell(
            title: "Credit 额度",
            value: model.qoderCreditSnapshot.map { "\(Int(round($0.usagePercentage * 100)))% (\($0.creditsUsed)/\($0.creditsTotal))" } ?? "--"
          )
          summaryCell(
            title: "今日对话",
            value: model.qoderSnapshot.map { "\($0.todayPrompts) 次" } ?? "--"
          )
        }
      case .grok:
        HStack(spacing: 10) {
          summaryCell(
            title: model.grokSnapshot?.windowTitle ?? "剩余用量",
            value: model.grokSnapshot.map { "\($0.remainingPercent)%" } ?? "--"
          )
          summaryCell(
            title: "当前套餐",
            value: model.grokSnapshot?.planDisplayName ?? "--"
          )
        }
      case .customImage:
        VStack(alignment: .leading, spacing: 5) {
          Label(model.customImageName ?? "尚未选择图片", systemImage: "photo")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)

          Text("用量自动刷新已暂停")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(AppGlassPanel(tint: .purple, radius: 14))
      }
    }
  }

  private var headerSubtitle: String {
    switch model.displayMode {
    case .codex: return "Codex 用量卡片"
    case .claudeCode: return "Claude Code 用量卡片"
    case .qoder: return "Qoder 用量卡片"
    case .grok: return "Grok 余量卡片"
    case .customImage: return "Linx68 自定义图片"
    }
  }

  private func popupResetText(_ date: Date?) -> String {
    guard let date else { return "重置时间 --" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd HH:mm"
    return "重置 " + formatter.string(from: date)
  }

  private func summaryCell(
    title: String,
    value: String,
    resetText: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .modifier(AppGlassPanel(tint: systemAccent, radius: 14))
    .overlay(alignment: .bottomTrailing) {
      if let resetText {
        Text(resetText)
          .font(.system(size: 8))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.trailing, 7)
          .padding(.bottom, 4)
      }
    }
  }

  private func chooseCustomImage() {
    let panel = NSOpenPanel()
    panel.title = "选择要显示在键盘上的图片"
    panel.prompt = "选择图片"
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    if panel.runModal() == .OK, let url = panel.url {
      model.selectCustomImage(at: url)
    }
  }
}

@MainActor
enum SettingsWindowPresenter {
  static func show(using openSettings: OpenSettingsAction) {
    NSApp.activate(ignoringOtherApps: true)

    if bringExistingWindowForward() {
      return
    }

    openSettings()
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      _ = bringExistingWindowForward()
    }
  }

  @discardableResult
  private static func bringExistingWindowForward() -> Bool {
    guard let window = NSApp.windows.first(where: isSettingsWindow) else {
      return false
    }

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.initialFirstResponder = window.contentView
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(nil)
    window.orderFrontRegardless()
    return true
  }

  static func isSettingsWindow(_ window: NSWindow) -> Bool {
    if window.identifier?.rawValue == "ai-monitor-settings" { return true }
    let title = window.title.lowercased()
    return title.contains("设置") || title.contains("settings")
  }
}

/// Capture this popover's own window, rather than relying on NSApp.keyWindow,
/// which may already point to Settings when the menu action is handled.
private final class MenuBarWindowReference {
  weak var window: NSWindow?
}

private struct MenuBarWindowReader: NSViewRepresentable {
  let reference: MenuBarWindowReference

  func makeNSView(context: Context) -> WindowView {
    WindowView(reference: reference)
  }

  func updateNSView(_ view: WindowView, context: Context) {
    reference.window = view.window
  }

  final class WindowView: NSView {
    let reference: MenuBarWindowReference

    init(reference: MenuBarWindowReference) {
      self.reference = reference
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      reference.window = window
    }
  }
}
