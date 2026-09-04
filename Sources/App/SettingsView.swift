import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var selectedPane: SettingsPane = .monitoring
  @State private var selectedLinxPane = 0

  private let intervals = [10, 30, 60, 300, 600, 1_800]
  private let brandAccent = Color(red: 62 / 255, green: 207 / 255, blue: 181 / 255)

  init(model: AppModel, initialPane: SettingsPane = .monitoring) {
    self.model = model
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: 196)

      Rectangle()
        .fill(Color.primary.opacity(0.08))
        .frame(width: 1)

      ZStack {
        detailBackground

        VStack(spacing: 0) {
          detailHeader

          detailBody
        }
      }
    }
    .frame(width: 890, height: 760)
    .background(Color(nsColor: .windowBackgroundColor))
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: activePane)
  }

  private var activePane: SettingsPane {
    selectedPane
  }

  @ViewBuilder
  private var detailBody: some View {
    switch activePane {
    case .linx:
      linxPane
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    case .monitoring, .general:
      ScrollView {
        detailContent
          .padding(.horizontal, 24)
          .padding(.top, 8)
          .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
    }
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      brandHeader

      AppGlassGroup {
      VStack(spacing: 6) {
        ForEach(SettingsPane.allCases) { pane in
          sidebarItem(pane)
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 8)
      }

      Spacer(minLength: 16)
    }
    .background(sidebarBackground)
  }

  private var brandHeader: some View {
    HStack(spacing: 11) {
      ZStack {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(
            LinearGradient(
              colors: [brandAccent, Color.blue.opacity(0.9)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )

        Image(systemName: "terminal.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 38, height: 38)
      .shadow(color: brandAccent.opacity(0.24), radius: 8, y: 4)

      VStack(alignment: .leading, spacing: 2) {
        Text(AppBrand.displayName)
          .font(.system(size: 14, weight: .semibold))
        Text("AI Monitor")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .padding(.bottom, 14)
  }

  private func sidebarItem(_ pane: SettingsPane) -> some View {
    Button {
      selectedPane = pane
    } label: {
      HStack(spacing: 11) {
        Image(systemName: pane.symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(selectedPane == pane ? pane.tint : .secondary)
          .frame(width: 26, height: 26)
          .background(
            selectedPane == pane ? pane.tint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )

        Text(pane.title)
          .font(.system(size: 13, weight: selectedPane == pane ? .semibold : .medium))

        Spacer(minLength: 0)
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .frame(height: 42)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .background {
        if selectedPane == pane {
          selectedSidebarBackground(tint: pane.tint)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selectedPane == pane ? .isSelected : [])
  }

  private var keyboardStatusBadge: some View {
    glassSurface(tint: connectionColor) {
      HStack(spacing: 9) {
        Circle()
          .fill(connectionColor)
          .frame(width: 8, height: 8)
          .shadow(color: connectionColor.opacity(0.45), radius: 4)

        VStack(alignment: .leading, spacing: 1) {
          Text(connectionTitle)
            .font(.caption.weight(.semibold))
          Text("键盘状态")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(11)
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var detailHeader: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(activePane.title)
          .font(.system(size: 22, weight: .semibold, design: .rounded))

        Text(activePane.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if activePane == .linx {
        keyboardStatusBadge
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 14)
  }

  @ViewBuilder
  private var detailContent: some View {
    switch activePane {
    case .monitoring:
      monitoringPane
    case .linx:
      linxPane
    case .general:
      generalPane
    }
  }

  private var linxPane: some View {
    VStack(spacing: 12) {
      Picker("Linx68 推送配置", selection: $selectedLinxPane) {
        Text("显示与预览").tag(0)
        Text("连接与同步").tag(1)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      if selectedLinxPane == 0 {
        displayPane
      } else {
        ScrollView { connectionPane }
          .scrollIndicators(.hidden)
      }
    }
  }

  private var displayPane: some View {
    HStack(alignment: .top, spacing: 16) {
      ScrollView {
        VStack(spacing: 16) {
          settingsCard(
          title: "显示内容",
          subtitle: "选择键盘屏幕上展示的信息",
          symbol: "rectangle.2.swap",
          tint: .blue
        ) {
          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 8),
              GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
          ) {
            displayModeOption(model.selectedAIMode, title: "AI 用量")
            displayModeOption(.customImage)
          }

          Divider().opacity(0.5)

          if model.displayMode == .customImage {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text(model.customImageName ?? "尚未选择图片")
                  .font(.callout.weight(.medium))
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text("自动裁切并保留顶部状态栏")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              regularGlassButton {
                chooseCustomImage()
              } label: {
                Label("选择", systemImage: "photo")
              }
            }
          } else if model.displayMode == .codex {
            Label(
              "自动读取 Codex 用量，并按设定间隔推送到键盘。",
              systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else if model.displayMode == .qoder {
            Label(
              "自动读取 Qoder 会话用量与状态，并按设定间隔推送到键盘。",
              systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else if model.displayMode == .grok {
            Label(
              "自动读取 Grok CLI 剩余额度，并按设定间隔推送到键盘。",
              systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else {
            Label(
              "自动统计 Claude Code token 用量与状态，并按设定间隔推送到键盘。",
              systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        if model.displayMode != .customImage {
          settingsCard(
            title: "配色",
            subtitle: colorSchemeSubtitle,
            symbol: "paintpalette",
            tint: model.usageCardColorScheme.palette.accent
          ) {
            LazyVGrid(
              columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
              ],
              spacing: 10
            ) {
              ForEach(UsageCardColorScheme.allCases) { colorScheme in
                usageColorOption(colorScheme)
              }
            }
          }

          if model.displayMode.isUsageMode {
            settingsCard(
              title: "风格",
              subtitle: "选择信息的组织方式与视觉语言",
              symbol: "rectangle.3.group",
              tint: model.usageCardColorScheme.palette.accent
            ) {
              LazyVGrid(
                columns: [
                  GridItem(.flexible(), spacing: 10),
                  GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
              ) {
                ForEach(UsageCardDesign.allCases) { design in
                  usageDesignOption(design)
                }
              }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }

        settingsCard(
          title: "输出设置",
          subtitle: "针对 Linx68 屏幕微调输出",
          symbol: "slider.horizontal.3",
          tint: .purple
        ) {
          VStack(spacing: 14) {
            settingRow(
              title: "顶部安全区",
              subtitle: "避开键盘固件状态栏"
            ) {
              Stepper(value: $model.safeAreaHeight, in: 44...80, step: 1) {
                Text("\(Int(model.safeAreaHeight)) px")
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                  .frame(width: 52, alignment: .trailing)
              }
              .labelsHidden()
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text("JPEG 质量")
                    .font(.callout.weight(.medium))
                  Text("仅影响发送到键盘的文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(model.jpegQuality * 100))%")
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
              }

              Slider(value: $model.jpegQuality, in: 0.5...1, step: 0.05)
                .tint(brandAccent)
            }
          }
        }

          glassSurface(tint: brandAccent) {
            HStack(spacing: 10) {
              Image(systemName: "sparkles")
                .foregroundStyle(brandAccent)
              Text("预览使用 Retina 2× 渲染，键盘输出保持 142×428。")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer(minLength: 0)
            }
            .padding(12)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .frame(maxWidth: .infinity)

      previewCard
        .frame(width: 204)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var previewCard: some View {
    settingsCard(
      title: "键盘预览",
      subtitle: "实时显示最终画面",
      symbol: "keyboard",
      tint: brandAccent
    ) {
      Group {
        if let previewImage = model.previewImage {
          Image(nsImage: previewImage)
            .resizable()
            .interpolation(.high)
        } else {
          ZStack {
            Color(red: 8 / 255, green: 11 / 255, blue: 18 / 255)
            VStack(spacing: 8) {
              Image(systemName: "photo")
                .font(.title2)
              Text("请选择图片")
                .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.65))
          }
        }
      }
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
      .clipped()
      .overlay(alignment: .top) {
        Text("状态栏安全区")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(.white.opacity(0.35))
          .padding(.top, 8)
      }
      .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(.white.opacity(0.12), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
      .frame(maxWidth: .infinity)

      Text(previewDescription)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
  }

  private var connectionPane: some View {
    VStack(spacing: 16) {
      settingsCard(
        title: "设备接口",
        subtitle: "连接 Linx68 图像上传服务",
        symbol: "network",
        tint: .blue
      ) {
        VStack(alignment: .leading, spacing: 7) {
          Text("图像 API 地址")
            .font(.caption)
            .foregroundStyle(.secondary)

          TextField("http://192.168.31.71/image/upload", text: $model.endpoint)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }

        HStack {
          Label("POST", systemImage: "arrow.up.doc")
          Text("image/jpeg")
          Spacer()
          Text("最长等待 20 秒")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      settingsCard(
        title: "自动同步",
        subtitle: "控制用量的后台刷新频率",
        symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
        tint: .orange
      ) {
        settingRow(
          title: "刷新间隔",
          subtitle: model.displayMode == .customImage ? "自定义图片模式下已暂停" : "有变化时自动推送"
        ) {
          Picker(
            "刷新间隔",
            selection: Binding(
              get: { model.refreshIntervalSeconds },
              set: { model.setRefreshInterval($0) }
            )
          ) {
            ForEach(intervals, id: \.self) { seconds in
              Text(intervalTitle(seconds)).tag(seconds)
            }
          }
          .labelsHidden()
          .frame(width: 120)
          .disabled(model.displayMode == .customImage)
        }
      }

      settingsCard(
        title: "运行状态",
        subtitle: "最近一次查询与推送结果",
        symbol: connectionSymbol,
        tint: connectionColor,
        showPushAction: true
      ) {
        statusRow(title: "当前状态", value: model.statusText, valueColor: connectionColor)
        Divider().opacity(0.5)
        statusRow(title: "用量刷新", value: model.lastRefreshText)
        Divider().opacity(0.5)
        statusRow(title: "键盘推送", value: model.lastUploadText)

        if let error = model.lastError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
    .frame(maxWidth: 620)
    .frame(maxWidth: .infinity)
  }

  private var monitoringPane: some View {
    VStack(spacing: 16) {
      settingsCard(
        title: "任务监控展示",
        subtitle: "跟随当前选择的 AI，同步任务状态",
        symbol: "circle.grid.3x1.fill",
        tint: .indigo
      ) {
        Text("当前 AI")
          .font(.caption).foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
          ForEach(DisplayMode.allCases.filter(\.isUsageMode)) { mode in
            monitoringOption(title: mode.title, symbol: mode.symbol,
              tint: monitoringTint(for: mode), isSelected: model.selectedAIMode == mode) {
                model.setSelectedAI(mode)
              }
          }
        }
        Toggle("状态栏展示任务监控", isOn: $model.showTaskStatusInMenuBar)
          .toggleStyle(.switch)
          .tint(brandAccent)
          .padding(.vertical, 6)
        if model.showTaskStatusInMenuBar {
          Text("原图标位置")
            .font(.caption).foregroundStyle(.secondary)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(MenuBarOriginalIconPosition.allCases) { position in
              monitoringOption(title: position.title,
                symbol: position == .hidden ? "eye.slash" : (position == .left ? "align.horizontal.left" : "align.horizontal.right"),
                tint: .indigo, isSelected: model.menuBarOriginalIconPosition == position) {
                  model.menuBarOriginalIconPosition = position
                }
            }
          }
        }
        Divider().opacity(0.5)
        HStack {
          Image(nsImage: TaskTrafficLight.makeImage(
            state: model.selectedActivityState, mode: model.displayMode))
          Text(model.taskStatusDescription).font(.caption)
        }
        Text("红灯等待授权/失败 · 黄灯进行中 · 绿灯完成/空闲。图片模式不监控任务。")
          .font(.caption).foregroundStyle(.secondary)
      }

      if model.selectedAIMode == .codex {
      settingsCard(
        title: "Codex 状态监控",
        subtitle: "用交通灯显示当前任务状态",
        symbol: "light.beacon.max.fill",
        tint: monitoringTint(for: .codex)
      ) {
        statusRow(
          title: "当前任务",
          value: model.codexActivityState.title,
          valueColor: activityColor
        )

        Divider().opacity(0.5)

        statusRow(
          title: "Hook 状态",
          value: model.codexHookStatusText,
          valueColor: hookStatusColor
        )

        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("黄灯进行中 · 红灯等待/失败 · 绿灯完成/空闲")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("应用会自动配置；首次使用请按 Codex 提示信任，或在 CLI 的 /hooks 中处理。")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }

          Spacer()

          regularGlassButton {
            model.installCodexActivityHooks()
          } label: {
            Label(
              model.codexHookInstallationState.isConfigured ? "修复 Hook" : "安装 Hook",
              systemImage: "wrench.and.screwdriver"
            )
          }
        }
      }

      }
      if model.selectedAIMode == .claudeCode {
      settingsCard(
        title: "Claude Code 状态监控",
        subtitle: "用交通灯显示当前任务状态",
        symbol: "light.beacon.max.fill",
        tint: monitoringTint(for: .claudeCode)
      ) {
        statusRow(
          title: "当前任务",
          value: model.claudeActivityState.title,
          valueColor: claudeActivityColor
        )

        Divider().opacity(0.5)

        statusRow(
          title: "Hook 状态",
          value: model.claudeHookStatusText,
          valueColor: claudeHookStatusColor
        )

        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("黄灯进行中 · 红灯等待/失败 · 绿灯完成/空闲")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("用量来自本地 ~/.claude/projects 会话记录；Hook 写入 ~/.claude/settings.json，如未生效请在 /hooks 中检查。")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }

          Spacer()

          regularGlassButton {
            model.installClaudeCodeActivityHooks()
          } label: {
            Label(
              model.claudeHookInstallationState.isConfigured ? "修复 Hook" : "安装 Hook",
              systemImage: "wrench.and.screwdriver"
            )
          }
        }
      }

      }
      if model.selectedAIMode == .qoder {
      settingsCard(
        title: "Qoder 用量监控",
        subtitle: "读取本地 Qoder 会话记录与额度",
        symbol: "sparkles",
        tint: monitoringTint(for: .qoder)
      ) {
        statusRow(
          title: "当前任务",
          value: model.qoderActivityState.title,
          valueColor: qoderActivityColor
        )

        Divider().opacity(0.5)

        statusRow(
          title: "数据源",
          value: model.qoderDataStatusText,
          valueColor: qoderActivityColor
        )

        if let credit = model.qoderCreditSnapshot, credit.hasData {
          Divider().opacity(0.5)

          statusRow(
            title: "Credit 额度",
            value: "\(credit.creditsUsed)/\(credit.creditsTotal) (\(credit.creditsPercentageDisplay))",
            valueColor: credit.isQuotaExceeded ? .red : qoderActivityColor
          )

          if credit.contextLimitTokens > 0 {
            Divider().opacity(0.5)

            statusRow(
              title: "上下文 Token",
              value: "\(ClaudeCodeTokenFormatter.string(from: credit.contextUsedTokens))/\(ClaudeCodeTokenFormatter.string(from: credit.contextLimitTokens))",
              valueColor: qoderActivityColor
            )
          }
        }

        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("黄灯进行中 · 红灯失败 · 绿灯完成/空闲")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("用量来自本地 ~/.qoder/projects 会话记录，额度来自运行日志。")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }

          Spacer()
        }
      }

      }
      if model.selectedAIMode == .grok {
      settingsCard(
        title: "Grok 余量监控",
        subtitle: "读取本机 Grok CLI 登录信息中的剩余额度",
        symbol: "sparkles",
        tint: monitoringTint(for: .grok)
      ) {
        statusRow(
          title: "当前任务",
          value: model.grokActivityState.title,
          valueColor: grokActivityColor
        )

        Divider().opacity(0.5)

        statusRow(
          title: "数据源",
          value: model.grokDataStatusText,
          valueColor: grokActivityColor
        )

        if let snapshot = model.grokSnapshot {
          Divider().opacity(0.5)

          statusRow(
            title: "剩余用量",
            value: "\(snapshot.remainingPercent)%",
            valueColor: snapshot.remainingPercent <= 10 ? .red : grokActivityColor
          )

          Divider().opacity(0.5)

          statusRow(
            title: "当前套餐",
            value: snapshot.planDisplayName,
            valueColor: grokActivityColor
          )

          if let resetDate = snapshot.periodEnd {
            Divider().opacity(0.5)

            statusRow(
              title: "下次重置",
              value: grokResetFormatter.string(from: resetDate),
              valueColor: grokActivityColor
            )
          }
        }

        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("黄灯进行中 · 绿灯空闲")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("余量来自本机 ~/.grok/auth.json 调用 Grok CLI 用量接口，卡片展示剩余百分比而非已用量。")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }

          Spacer()
        }
      }

      }
    }
    .frame(maxWidth: 620)
    .frame(maxWidth: .infinity)
  }

  private var generalPane: some View {
    VStack(spacing: 16) {
      settingsCard(
        title: "启动设置",
        subtitle: "控制应用随系统登录自动运行",
        symbol: "power",
        tint: .green
      ) {
        settingRow(
          title: "登录时自动启动",
          subtitle: "应用会静默驻留在菜单栏"
        ) {
          Toggle(
            "登录时自动启动",
            isOn: Binding(
              get: { model.launchAtLogin },
              set: { model.updateLaunchAtLogin($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(brandAccent)
        }
      }

      settingsCard(
        title: "关于",
        subtitle: "AI Monitor · AI 任务监控与 Linx68 推送",
        symbol: "info.circle",
        tint: brandAccent
      ) {
        HStack(spacing: 14) {
          ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [brandAccent, Color.blue],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            Image(systemName: "terminal.fill")
              .font(.system(size: 23, weight: .semibold))
              .foregroundStyle(.white)
          }
          .frame(width: 52, height: 52)

          VStack(alignment: .leading, spacing: 4) {
            Text(AppBrand.displayName)
              .font(.headline)
            Text("监控 AI 任务状态，并将用量或自定义图片推送到 Linx68。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
      }
    }
    .frame(maxWidth: 620)
    .frame(maxWidth: .infinity)
  }

  private var detailBackground: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)

      RadialGradient(
        colors: [brandAccent.opacity(0.12), .clear],
        center: .topTrailing,
        startRadius: 0,
        endRadius: 420
      )

      RadialGradient(
        colors: [Color.blue.opacity(0.08), .clear],
        center: .bottomLeading,
        startRadius: 0,
        endRadius: 460
      )
    }
    .ignoresSafeArea()
  }

  private var sidebarBackground: some View {
    ZStack {
      if reduceTransparency {
        Color(nsColor: .windowBackgroundColor)
      } else {
        AppFrostedBackdrop(material: .sidebar, blendingMode: .behindWindow)
      }

      LinearGradient(
        colors: [brandAccent.opacity(0.08), Color.blue.opacity(0.03), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private func selectedSidebarBackground(tint: Color) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    if #available(macOS 26.0, *), !reduceTransparency {
      Color.clear
        .glassEffect(.regular.tint(tint.opacity(0.1)), in: shape)
        .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
    } else {
      shape
        .fill(tint.opacity(0.1))
        .overlay { shape.stroke(Color.primary.opacity(0.08), lineWidth: 1) }
    }
  }

  private func settingsCard<Content: View>(
    title: String,
    subtitle: String,
    symbol: String,
    tint: Color,
    showPushAction: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    glassSurface(tint: tint) {
      VStack(alignment: .leading, spacing: 13) {
        HStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

          VStack(alignment: .leading, spacing: 1) {
            Text(title)
              .font(.headline)
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 0)
          if showPushAction {
            prominentGlassButton {
              model.pushNow()
            } label: {
              Label(model.isSyncing ? "正在推送" : "立即推送", systemImage: "paperplane.fill")
            }
            .disabled(model.isSyncing)
          }
        }

        content()
      }
      .padding(17)
    }
  }

  private func displayModeOption(_ mode: DisplayMode, title: String? = nil) -> some View {
    let isSelected = model.displayMode == mode
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    return Button {
      model.setDisplayMode(mode)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: mode.symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isSelected ? brandAccent : .secondary)
          .frame(width: 26, height: 26)
          .background(
            (isSelected ? brandAccent : Color.primary).opacity(isSelected ? 0.12 : 0.05),
            in: RoundedRectangle(cornerRadius: 8)
          )

        Text(title ?? mode.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? brandAccent.opacity(0.09) : Color.primary.opacity(0.025), in: shape)
      .overlay {
        shape.stroke(
          isSelected ? brandAccent.opacity(0.55) : Color.primary.opacity(0.07),
          lineWidth: isSelected ? 1.25 : 1
        )
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func monitoringOption(
    title: String, symbol: String, tint: Color, isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    return Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 30, height: 30)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
          .opacity(isSelected ? 1 : 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? tint.opacity(0.09) : Color.primary.opacity(0.025), in: shape)
      .overlay {
        shape.stroke(isSelected ? tint.opacity(0.55) : Color.primary.opacity(0.07),
          lineWidth: isSelected ? 1.25 : 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func monitoringTint(for mode: DisplayMode) -> Color {
    switch mode {
    case .codex: return .teal
    case .claudeCode: return .orange
    case .qoder: return .purple
    case .grok: return .blue
    case .customImage: return .indigo
    }
  }

  private func usageColorOption(_ colorScheme: UsageCardColorScheme) -> some View {
    let isSelected = model.usageCardColorScheme == colorScheme
    let palette = colorScheme.palette
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    return Button {
      model.setUsageCardColorScheme(colorScheme)
    } label: {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(palette.background)

          Image(systemName: colorScheme.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.accent)
        }
        .frame(width: 34, height: 34)
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(palette.border, lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(colorScheme.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)

          HStack(spacing: 4) {
            HStack(spacing: 2) {
              Circle().fill(palette.accent)
              Circle().fill(palette.primaryText)
            }
            .frame(width: 12, height: 5)

            Text(colorScheme.subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(palette.accent)
          .opacity(isSelected ? 1 : 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? palette.accent.opacity(0.09) : Color.primary.opacity(0.025), in: shape)
      .overlay {
        shape.stroke(
          isSelected ? palette.accent.opacity(0.55) : Color.primary.opacity(0.07),
          lineWidth: isSelected ? 1.25 : 1
        )
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func usageDesignOption(_ design: UsageCardDesign) -> some View {
    let isSelected = model.usageCardDesign == design
    let tint = model.usageCardColorScheme.palette.accent
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    return Button {
      model.setUsageCardDesign(design)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: design.symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 34, height: 34)
          .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
          .overlay {
            RoundedRectangle(cornerRadius: 9)
              .stroke(tint.opacity(0.24), lineWidth: 1)
          }

        VStack(alignment: .leading, spacing: 2) {
          Text(design.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
          Text(design.subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
          .opacity(isSelected ? 1 : 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? tint.opacity(0.09) : Color.primary.opacity(0.025), in: shape)
      .overlay {
        shape.stroke(
          isSelected ? tint.opacity(0.55) : Color.primary.opacity(0.07),
          lineWidth: isSelected ? 1.25 : 1
        )
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private func glassSurface<Content: View>(
    tint: Color,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .modifier(AppGlassPanel(tint: tint))
  }

  private func settingRow<Accessory: View>(
    title: String,
    subtitle: String,
    @ViewBuilder accessory: () -> Accessory
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      accessory()
    }
  }

  private func statusRow(
    title: String,
    value: String,
    valueColor: Color = .secondary
  ) -> some View {
    HStack {
      Text(title)
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.callout.weight(.medium))
        .foregroundStyle(valueColor)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func regularGlassButton<LabelContent: View>(
    action: @escaping () -> Void,
    @ViewBuilder label: () -> LabelContent
  ) -> some View {
    Button(action: action, label: label)
      .modifier(AppGlassButton())
  }

  @ViewBuilder
  private func prominentGlassButton<LabelContent: View>(
    action: @escaping () -> Void,
    @ViewBuilder label: () -> LabelContent
  ) -> some View {
    Button(action: action, label: label)
      .modifier(AppGlassButton(prominent: true))
  }

  private var connectionTitle: String {
    switch model.keyboardConnectionState {
    case .disconnected: return "键盘未连接"
    case .connected: return "键盘已连接"
    case .pushFailed: return "推送失败"
    }
  }

  private var previewDescription: String {
    switch model.displayMode {
    case .codex:
      return "\(model.usageCardDesign.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .claudeCode:
      return "Claude Code · \(model.usageCardDesign.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .qoder:
      return "Qoder · \(model.usageCardDesign.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .grok:
      return "Grok · \(model.usageCardDesign.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .customImage:
      return "\(model.displayMode.title) · 顶部 \(Int(model.safeAreaHeight))px 留空"
    }
  }

  private var colorSchemeSubtitle: String {
    switch model.displayMode {
    case .codex: return "选择 Codex 用量卡片的色彩方案"
    case .claudeCode: return "选择 Claude Code 卡片的色彩方案"
    case .qoder: return "选择 Qoder 卡片的色彩方案"
    case .grok: return "选择 Grok 卡片的色彩方案"
    case .customImage: return "选择卡片的色彩方案"
    }
  }

  private var connectionSymbol: String {
    switch model.keyboardConnectionState {
    case .disconnected: return "keyboard.badge.ellipsis"
    case .connected: return "checkmark.circle.fill"
    case .pushFailed: return "exclamationmark.triangle.fill"
    }
  }

  private var connectionColor: Color {
    switch model.keyboardConnectionState {
    case .disconnected: return .secondary
    case .connected: return brandAccent
    case .pushFailed: return .orange
    }
  }

  private var activityColor: Color {
    switch model.codexActivityState {
    case .idle: return .green
    case .finished: return .green
    case .running: return .yellow
    case .awaitingAuthorization: return .red
    case .toolFailed: return .red
    }
  }

  private var hookStatusColor: Color {
    switch model.codexHookInstallationState {
    case .notInstalled: return .secondary
    case .configured: return .orange
    case .active: return brandAccent
    case .failed: return .red
    }
  }

  private var claudeActivityColor: Color {
    switch model.claudeActivityState {
    case .idle: return .green
    case .finished: return .green
    case .running: return .yellow
    case .awaitingAuthorization: return .red
    case .toolFailed: return .red
    }
  }

  private var claudeHookStatusColor: Color {
    switch model.claudeHookInstallationState {
    case .notInstalled: return .secondary
    case .configured: return .orange
    case .active: return brandAccent
    case .failed: return .red
    }
  }

  private var qoderActivityColor: Color {
    switch model.qoderActivityState {
    case .idle: return .green
    case .finished: return .green
    case .running: return .yellow
    case .awaitingAuthorization: return .red
    case .toolFailed: return .red
    }
  }

  private var grokActivityColor: Color {
    switch model.grokActivityState {
    case .idle: return .green
    case .finished: return .green
    case .running: return .yellow
    case .awaitingAuthorization: return .red
    case .toolFailed: return .red
    }
  }

  private var grokResetFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter
  }

  private func intervalTitle(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) 秒" }
    return "\(seconds / 60) 分钟"
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

enum SettingsPane: String, CaseIterable, Identifiable {
  case monitoring
  case linx
  case general

  var id: String { rawValue }

  var title: String {
    switch self {
    case .monitoring: return "状态监控"
    case .linx: return "Linx68推送"
    case .general: return "通用"
    }
  }

  var subtitle: String {
    switch self {
    case .monitoring: return "配置菜单栏展示，查看各 AI 的任务状态"
    case .linx: return "配置键盘画面、设备连接与同步推送"
    case .general: return "启动行为与应用信息"
    }
  }

  var symbol: String {
    switch self {
    case .monitoring: return "light.beacon.max.fill"
    case .linx: return "keyboard"
    case .general: return "gearshape"
    }
  }

  var tint: Color {
    switch self {
    case .monitoring: return .green
    case .linx: return .blue
    case .general: return .gray
    }
  }
}
