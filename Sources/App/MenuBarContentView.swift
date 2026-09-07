import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
  @ObservedObject var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      usageSummary

      VStack(alignment: .leading, spacing: 5) {
        Label(
          model.statusText,
          systemImage: model.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .foregroundStyle(model.lastError == nil ? Color.secondary : Color.orange)

        Text("上次推送：\(model.lastUploadText)")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let error = model.lastError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .modifier(AppGlassPanel(tint: model.lastError == nil ? .teal : .orange, radius: 16))

      AppGlassGroup {
      HStack {
        if model.displayMode != .customImage {
          Button {
            model.refreshOnly()
          } label: {
            Label("刷新", systemImage: "arrow.clockwise")
          }
          .disabled(model.isSyncing)
        } else {
          Button {
            chooseCustomImage()
          } label: {
            Label("选择图片", systemImage: "photo")
          }
          .disabled(model.isSyncing)
        }

        Button {
          model.pushNow()
        } label: {
          Label("立即推送", systemImage: "paperplane")
        }
        .modifier(AppGlassButton(prominent: true))
        .disabled(model.isSyncing)

        Spacer()
      }
      .modifier(AppGlassButton())
      }

      Divider()

      AppGlassGroup {
      HStack {
        Button {
          SettingsWindowPresenter.show(using: openSettings)
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
    .modifier(AppGlassPanel(tint: .teal, radius: 24))
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

      if model.isSyncing {
        ProgressView()
          .controlSize(.small)
      }
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

  private func summaryCell(title: String, value: String, resetText: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .modifier(AppGlassPanel(tint: .teal, radius: 14))
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
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    return true
  }

  static func isSettingsWindow(_ window: NSWindow) -> Bool {
    let title = window.title.lowercased()
    return title.contains("设置") || title.contains("settings")
  }
}
