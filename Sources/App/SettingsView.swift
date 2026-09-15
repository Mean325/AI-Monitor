import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsChrome {
  static let cornerRadius: CGFloat = 16
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  var checkForUpdates: () -> Void = {}
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var selectedPane: SettingsPane = .monitoring
  @State private var selectedLinxPane = 0
  @State private var searchText = ""
  @State private var hoveredPane: SettingsPane?
  @State private var backHistory: [SettingsPane] = []
  @State private var forwardHistory: [SettingsPane] = []
  @Environment(\.controlActiveState) private var controlActiveState
  @State private var showingPushRequestDetails = false

  private let intervals = [10, 30, 60, 300, 600, 1_800]
  private let brandAccent = Color(red: 62 / 255, green: 207 / 255, blue: 181 / 255)
  private var systemAccent: Color { Color(nsColor: .controlAccentColor) }

  init(
    model: AppModel,
    initialPane: SettingsPane = .monitoring,
    checkForUpdates: @escaping () -> Void = {}
  ) {
    self.model = model
    self.checkForUpdates = checkForUpdates
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: 215)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.cornerRadius, style: .continuous))
        .padding(.leading, 8)
        .padding(.vertical, 8)

      VStack(spacing: 0) {
        navigationBar
        detailBody
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity,
           minHeight: 600, idealHeight: 660, maxHeight: .infinity)
    .font(.system(size: 13))
    .controlSize(.small)
    .background(detailCanvasBackground)
    .toolbar(.hidden, for: .windowToolbar)
    .toolbarBackground(.hidden, for: .windowToolbar)
    .background(SettingsWindowConfigurator(pane: selectedPane))
    .background {
      SettingsPreviewCompanion(
        isPresented: selectedPane == .linx && model.isLinxEnabled && selectedLinxPane == 0,
        content: AnyView(previewCard
          .frame(width: 188)
          .fixedSize(horizontal: false, vertical: true)
          .font(.system(size: 13))
          .controlSize(.small)
          .environment(\.colorScheme, colorScheme))
      )
    }
    .ignoresSafeArea(.container, edges: .top)
    .sheet(isPresented: $showingPushRequestDetails) {
      pushRequestDetails
    }
  }

  private var activePane: SettingsPane {
    selectedPane
  }

  private var navigationBar: some View {
    HStack(spacing: 0) {
      HStack(spacing: 0) {
        Button {
          guard let pane = backHistory.popLast() else { return }
          forwardHistory.append(selectedPane)
          selectedPane = pane
        } label: {
          Image(systemName: "chevron.left").frame(width: 34, height: 34)
        }
        .disabled(backHistory.isEmpty)
        .help("返回")
        .accessibilityLabel("返回")

        Divider().frame(height: 16).opacity(0.4)

        Button {
          guard let pane = forwardHistory.popLast() else { return }
          backHistory.append(selectedPane)
          selectedPane = pane
        } label: {
          Image(systemName: "chevron.right").frame(width: 34, height: 34)
        }
        .disabled(forwardHistory.isEmpty)
        .help("前进")
        .accessibilityLabel("前进")
      }
      .font(.system(size: 15, weight: .medium))
      .buttonStyle(.plain)
      .background(systemGroupBackground, in: Capsule())
      Spacer()
    }
    .padding(.leading, 8)
    .frame(height: 52)
  }

  private var detailBody: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 10) {
          detailHeader.id("paneTop")
          detailContent
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
      }
      .scrollIndicators(.automatic)
      .onChange(of: selectedPane) { _, _ in
        proxy.scrollTo("paneTop", anchor: .top)
      }
      .onChange(of: selectedLinxPane) { _, _ in
        proxy.scrollTo("paneTop", anchor: .top)
      }
    }
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      SettingsTrafficLights()
        .frame(width: 70, height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.top, 10)
        .padding(.bottom, 28)

      HStack(spacing: 5) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("搜索", text: $searchText)
          .textFieldStyle(.plain)
          .accessibilityLabel("搜索设置")
        if !searchText.isEmpty {
          Button { searchText = "" } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清除搜索")
        }
      }
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(Color.primary.opacity(0.065), in: Capsule())
      .padding(.horizontal, 10)

      brandHeader

      ScrollView {
        VStack(spacing: sidebarItemSpacing) {
          ForEach(SettingsPane.allCases.filter {
            searchText.isEmpty || ($0.title + $0.subtitle + $0.searchKeywords)
              .localizedCaseInsensitiveContains(searchText)
          }) { pane in
            sidebarItem(pane)
          }
          if !searchText.isEmpty && !SettingsPane.allCases.contains(where: {
            ($0.title + $0.subtitle + $0.searchKeywords).localizedCaseInsensitiveContains(searchText)
          }) {
            Text("未找到设置").foregroundStyle(.secondary).padding(.top, 12)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
      }
      .scrollIndicators(.hidden)
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
      .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

      VStack(alignment: .leading, spacing: 2) {
        Text(AppBrand.displayName)
          .font(.system(size: 14, weight: .semibold))
        Text("应用设置")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 20)
  }

  private let sidebarItemHeight: CGFloat = 32
  private let sidebarItemSpacing: CGFloat = 0

  private var sidebarSelectionAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.2)
  }

  private func sidebarItem(_ pane: SettingsPane) -> some View {
    let isSelected = selectedPane == pane
    let emphasized = isSelected && controlActiveState != .inactive
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    return Button {
      guard selectedPane != pane else { return }
      backHistory.append(selectedPane)
      forwardHistory.removeAll()
      withAnimation(sidebarSelectionAnimation) { selectedPane = pane }
    } label: {
      HStack(spacing: 7) {
        SettingsSystemIcon(kind: pane.systemIcon, size: 20)
        Text(pane.title)
          .font(.system(size: 13))
          .foregroundStyle(emphasized ? Color.white : Color.primary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .frame(height: sidebarItemHeight)
      .background(isSelected ? (emphasized ? Color(nsColor: .selectedContentBackgroundColor) : Color.primary.opacity(0.10)) : Color.primary.opacity(hoveredPane == pane ? 0.04 : 0), in: shape)
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .onHover { hoveredPane = $0 ? pane : nil }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var keyboardStatusPanel: some View {
    keyboardStatusContent
  }

  private var keyboardStatusContent: some View {
    VStack(spacing: 10) {
      statusRow(
        title: "设备名称",
        value: model.bluetoothKeyboardInfo?.name ?? "未发现 Linx68",
        valueColor: bluetoothConnectionColor
      )

      Divider().opacity(0.5)
      statusRow(
        title: "蓝牙状态",
        value: model.bluetoothKeyboardInfo?.isConnected == true ? "已连接" : "未连接",
        valueColor: bluetoothConnectionColor
      )

      Divider().opacity(0.5)
      statusRow(title: "电量", value: bluetoothBatteryText)

      if let address = model.bluetoothKeyboardInfo?.address {
        Divider().opacity(0.5)
        statusRow(title: "设备地址", value: address)
      }

      if model.bluetoothKeyboardInfo?.isConnected != true {
        Divider().opacity(0.5)
        Button {
          openBluetoothSettings()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "gear")
            Text("点击打开蓝牙设置并配对设备")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(systemAccent)
        .help("打开系统蓝牙设置")
      }

      Divider().opacity(0.5)

      Button {
        showingPushRequestDetails = true
      } label: {
        HStack(spacing: 8) {
          Text("屏幕推送")
            .foregroundStyle(.secondary)
          Spacer(minLength: 12)
          Text(lastPushSummary)
            .foregroundStyle(lastPushColor)
            .lineLimit(1)
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("查看最近一次 HTTP 请求详情")
    }
    .frame(maxWidth: .infinity)
    .onAppear {
      model.refreshBluetoothKeyboardInfo()
    }
  }

  private var pushRequestDetails: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: lastPushSymbol)
          .font(.title2)
          .foregroundStyle(lastPushColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("屏幕推送详情")
            .font(.headline)
          Text(lastPushSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      Divider()

      if let request = model.lastPushRequest {
        VStack(spacing: 10) {
          statusRow(title: "请求方法", value: "POST")
          Divider().opacity(0.5)
          statusRow(title: "内容类型", value: "image/jpeg")
          Divider().opacity(0.5)
          detailTextRow(title: "请求地址", value: request.endpoint)
          Divider().opacity(0.5)
          statusRow(title: "开始时间", value: pushDateText(request.startedAt))

          if let completedAt = request.completedAt {
            Divider().opacity(0.5)
            statusRow(title: "完成时间", value: pushDateText(completedAt))
          }

          switch request.outcome {
          case .pending:
            Divider().opacity(0.5)
            statusRow(title: "请求状态", value: "请求中", valueColor: .blue)
          case .succeeded(let statusCode, let responseText):
            Divider().opacity(0.5)
            statusRow(title: "HTTP 状态", value: String(statusCode), valueColor: brandAccent)
            if !responseText.isEmpty {
              Divider().opacity(0.5)
              detailTextRow(title: "响应内容", value: responseText)
            }
          case .failed(let statusCode, let responseText, let message):
            Divider().opacity(0.5)
            statusRow(
              title: "HTTP 状态",
              value: statusCode.map(String.init) ?? "未收到响应",
              valueColor: .red
            )
            Divider().opacity(0.5)
            detailTextRow(title: "错误信息", value: message, color: .red)
            if let responseText, !responseText.isEmpty {
              Divider().opacity(0.5)
              detailTextRow(title: "响应内容", value: responseText)
            }
          }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
      } else {
        ContentUnavailableView(
          "尚无推送记录",
          systemImage: "arrow.up.doc",
          description: Text("完成一次屏幕推送后，这里会显示 HTTP 请求详情。")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
      }

      HStack {
        Spacer()
        Button("完成") {
          showingPushRequestDetails = false
        }
        .modifier(AppGlassButton(prominent: true))
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 480)
  }

  private func detailTextRow(title: String, value: String, color: Color = .primary) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(color)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var detailHeader: some View {
    VStack(spacing: 0) {
      SettingsSystemIcon(kind: activePane.systemIcon, size: 52)
        .padding(.bottom, 10)

      Text(activePane.title)
        .font(.system(size: 22, weight: .bold))
        .padding(.bottom, 2)
      Text(activePane.subtitle)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
    .padding(.vertical, 24)
    .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
      linxMasterControl

      if model.isLinxEnabled {
        Picker("Linx68 推送配置", selection: $selectedLinxPane) {
          Text("显示与预览").tag(0)
          Text("连接与同步").tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if selectedLinxPane == 0 {
          displayPane
        } else {
          connectionPane
        }
      }
    }
    .animation(sidebarSelectionAnimation, value: model.isLinxEnabled)
  }

  private var linxMasterControl: some View {
    settingsCard(
      title: "Linx68",
      subtitle: model.isLinxEnabled ? "已开启自动同步与键盘推送" : "已暂停所有同步与推送",
      symbol: "keyboard",
      tint: brandAccent,
      showLinxToggle: true
    ) {
      keyboardStatusPanel
    }
  }

  private var displayPane: some View {
    VStack(spacing: 10) {
          settingsCard(
          title: "显示内容",
          subtitle: "选择键盘屏幕上展示的信息",
          symbol: "rectangle.2.swap",
          tint: .blue
        ) {
          AppGlassGroup {
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
            tint: selectedColorAccent
          ) {
            AppGlassGroup {
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
          }

          if model.displayMode.isUsageMode {
            settingsCard(
              title: "风格",
              subtitle: "选择信息的组织方式与视觉语言",
              symbol: "rectangle.3.group",
              tint: selectedColorAccent
            ) {
              AppGlassGroup {
                LazyVGrid(
                  columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                  ],
                  spacing: 10
                ) {
                  ForEach(UsageCardDesign.selectableCases(for: model.displayMode)) { design in
                    usageDesignOption(design)
                  }
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
                .tint(systemAccent)
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
    .frame(maxWidth: .infinity, alignment: .top)
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
      .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
      .frame(maxWidth: .infinity)

      Text(previewDescription)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
  }

  private var connectionPane: some View {
    VStack(spacing: 10) {
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
    .frame(maxWidth: .infinity)
  }

  private var monitoringPane: some View {
    VStack(spacing: 10) {
      settingsCard(
        title: "任务监控展示",
        subtitle: "跟随当前选择的 AI，同步任务状态",
        symbol: "circle.grid.2x2.fill",
        tint: .indigo
      ) {
        Text("当前 AI")
          .font(.caption).foregroundStyle(.secondary)
        AppGlassGroup {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(DisplayMode.allCases.filter(\.isUsageMode)) { mode in
              monitoringOption(
                title: mode.title,
                mode: mode,
                tint: monitoringTint(for: mode),
                isSelected: model.selectedAIMode == mode
              ) {
                model.setSelectedAI(mode)
              }
            }
          }
        }
        HStack {
          Text("状态栏展示任务监控")
          Spacer()
          Toggle("状态栏展示任务监控", isOn: $model.showTaskStatusInMenuBar)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(systemAccent)
        }
        .padding(.vertical, 6)
        if model.showTaskStatusInMenuBar {
          HStack {
            Image(nsImage: TaskTrafficLight.makeImage(
              state: model.selectedActivityState, mode: model.selectedAIMode))
            Text(model.taskStatusDescription).font(.caption)
          }
          Text("红灯等待授权/失败 · 黄灯进行中 · 绿灯完成/空闲。")
            .font(.caption).foregroundStyle(.secondary)
        }

        Divider().opacity(0.5)

        HStack {
          Text("状态栏展示用量")
          Spacer()
          Toggle("状态栏展示用量", isOn: $model.showUsageInMenuBar)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(systemAccent)
        }
        .padding(.vertical, 6)
        if model.showUsageInMenuBar {
          Text("原图标位置")
            .font(.caption).foregroundStyle(.secondary)
          AppGlassGroup {
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
        }
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
    .frame(maxWidth: .infinity)
  }

  private var generalPane: some View {
    VStack(spacing: 10) {
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
          .tint(systemAccent)
        }
      }

      settingsCard(
        title: "版本更新",
        subtitle: "通过 GitHub Releases 获取并安装新版本",
        symbol: "arrow.triangle.2.circlepath",
        tint: .blue
      ) {
        settingRow(
          title: AppBrand.versionDescription,
          subtitle: "发布版每天自动检查一次，也可以立即检查"
        ) {
          regularGlassButton(action: checkForUpdates) {
            Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
          }
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
            Text(AppBrand.versionDescription)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
            Text("监控 AI 任务状态，并将用量或自定义图片推送到 Linx68。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
      }
    }
    .frame(maxWidth: .infinity)
  }



  private var sidebarBackground: some View {
    ZStack {
      if reduceTransparency {
        sidebarOpaqueBackground
      } else {
        AppFrostedBackdrop(material: .sidebar, blendingMode: .behindWindow)
      }

      sidebarMaterialWash
    }
  }

  private var detailCanvasBackground: Color {
    colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white
  }

  private var sidebarOpaqueBackground: Color {
    colorScheme == .dark
      ? Color(nsColor: .underPageBackgroundColor)
      : Color(white: 0.97)
  }

  private var sidebarMaterialWash: Color {
    colorScheme == .dark
      ? Color.black.opacity(0.10)
      : Color.white.opacity(0.72)
  }









  private var systemGroupBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.07) : Color(white: 0.965)
  }

  private func settingsCard<Content: View>(
    title: String,
    subtitle: String,
    symbol: String,
    tint: Color,
    showLinxToggle: Bool = false,
    showPushAction: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        SettingsSystemIcon(kind: .forSymbol(symbol), size: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.system(size: 13, weight: .medium))
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
        if showLinxToggle {
          Toggle(
            "启用 Linx68",
            isOn: Binding(
              get: { model.isLinxEnabled },
              set: { model.setLinxEnabled($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(brandAccent)
          .accessibilityLabel("启用 Linx68")
        } else if showPushAction {
          prominentGlassButton {
            model.pushNow()
          } label: {
            Label(model.isSyncing ? "正在推送" : "立即推送", systemImage: "paperplane.fill")
          }
          .disabled(model.isSyncing)
        }
      }

      Divider()
        .opacity(0.55)

      content()
    }
    .padding(12)
    .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
          .foregroundStyle(isSelected ? systemAccent : .secondary)
          .frame(width: 26, height: 26)
          .background(
            (isSelected ? systemAccent : Color.primary).opacity(isSelected ? 0.12 : 0.05),
            in: RoundedRectangle(cornerRadius: 8)
          )

        Text(title ?? mode.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer(minLength: 0)

        Image(systemName: isSelected ? "circle.inset.filled" : "circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? systemAccent : Color.secondary)
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SettingsChoiceSurface(tint: systemAccent, isSelected: isSelected))
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func monitoringOption(
    title: String, mode: DisplayMode, tint: Color, isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    monitoringOption(
      title: title,
      icon: AnyView(BrandLogoView(mode: mode, size: 30)),
      tint: tint,
      isSelected: isSelected,
      action: action
    )
  }

  private func monitoringOption(
    title: String, symbol: String, tint: Color, isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    monitoringOption(
      title: title,
      icon: AnyView(
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(systemAccent)
          .frame(width: 30, height: 30)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      ),
      tint: tint,
      isSelected: isSelected,
      action: action
    )
  }

  private func monitoringOption(
    title: String, icon: AnyView, tint: Color, isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    return Button(action: action) {
      HStack(spacing: 8) {
        icon
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: isSelected ? "circle.inset.filled" : "circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? systemAccent : Color.secondary)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SettingsChoiceSurface(tint: systemAccent, isSelected: isSelected))
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
    let swatches = colorScheme.previewSwatches
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    return Button {
      model.setUsageCardColorScheme(colorScheme)
    } label: {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(colorOptionIconFill(colorScheme, palette: palette))

          Image(systemName: colorScheme.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colorScheme == .rainbow ? Color.white : palette.accent)
        }
        .frame(width: 34, height: 34)
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(palette.border, lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(colorScheme.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)

          HStack(spacing: 6) {
            HStack(spacing: 2) {
              ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                Circle().fill(color)
              }
            }
            .frame(width: CGFloat(swatches.count * 6), height: 5)

            Text(colorScheme.subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: isSelected ? "circle.inset.filled" : "circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? palette.accent : Color.secondary)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SettingsChoiceSurface(tint: palette.accent, isSelected: isSelected))
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func usageDesignOption(_ design: UsageCardDesign) -> some View {
    let isSelected = model.usageCardDesign.resolved(for: model.displayMode) == design
    let tint = selectedColorAccent
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

        Image(systemName: isSelected ? "circle.inset.filled" : "circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? systemAccent : Color.secondary)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SettingsChoiceSurface(tint: systemAccent, isSelected: isSelected))
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
      .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12))
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

  private var lastPushSummary: String {
    guard let request = model.lastPushRequest else { return "尚无推送记录" }
    switch request.outcome {
    case .pending:
      return "正在请求…"
    case .succeeded(let statusCode, _):
      return "成功 · HTTP \(statusCode)"
    case .failed(let statusCode, _, _):
      return statusCode.map { "失败 · HTTP \($0)" } ?? "请求失败"
    }
  }

  private var lastPushSymbol: String {
    guard let request = model.lastPushRequest else { return "minus.circle" }
    switch request.outcome {
    case .pending: return "clock.arrow.circlepath"
    case .succeeded: return "checkmark.circle.fill"
    case .failed: return "exclamationmark.triangle.fill"
    }
  }

  private var lastPushColor: Color {
    guard let request = model.lastPushRequest else { return .secondary }
    switch request.outcome {
    case .pending: return .blue
    case .succeeded: return brandAccent
    case .failed: return .red
    }
  }

  private func pushDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
  }

  private var bluetoothConnectionColor: Color {
    model.bluetoothKeyboardInfo?.isConnected == true ? brandAccent : .secondary
  }

  private var bluetoothBatteryText: String {
    guard model.bluetoothKeyboardInfo?.isConnected == true else { return "--" }
    guard let battery = model.bluetoothKeyboardInfo?.batteryPercent else { return "不可用" }
    return "\(battery)%"
  }

  private func openBluetoothSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  private var previewDescription: String {
    let design = model.usageCardDesign.resolved(for: model.displayMode)
    switch model.displayMode {
    case .codex:
      return "\(design.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .claudeCode:
      return "Claude Code · \(design.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .qoder:
      return "Qoder · \(design.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
    case .grok:
      return "Grok · \(design.title) · \(model.usageCardColorScheme.title) · 顶部 \(Int(model.safeAreaHeight))px"
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

  private var selectedColorAccent: Color {
    model.usageCardColorScheme.palette(remainingPercent: liveRemainingPercent).accent
  }

  private var liveRemainingPercent: Int? {
    switch model.displayMode {
    case .codex:
      return model.snapshot?.remainingPercent
    case .grok:
      return model.grokSnapshot?.remainingPercent
    case .qoder:
      return model.qoderCreditSnapshot?.remainingPercent
    case .claudeCode, .customImage:
      return nil
    }
  }

  private func colorOptionIconFill(
    _ colorScheme: UsageCardColorScheme,
    palette: UsageCardPalette
  ) -> AnyShapeStyle {
    if colorScheme == .rainbow {
      return AnyShapeStyle(
        LinearGradient(
          colors: colorScheme.previewSwatches,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    return AnyShapeStyle(palette.background)
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

  var searchKeywords: String {
    switch self {
    case .monitoring: return "Codex Claude Qoder Grok AI 菜单栏 Hook 任务 状态"
    case .linx: return "键盘 图片 预览 颜色 主题 蓝牙 电量 同步 接口 刷新 推送"
    case .general: return "启动 登录 版本 更新 关于"
    }
  }

  var subtitle: String {
    switch self {
    case .monitoring: return "配置菜单栏展示，查看各 AI 的任务状态"
    case .linx: return "配置键盘画面、设备连接与同步推送"
    case .general: return "启动行为与应用信息"
    }
  }

  fileprivate var systemIcon: SettingsSystemIcon.Kind {
    switch self {
    case .monitoring: return .monitoring
    case .linx: return .keyboard
    case .general: return .general
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

private struct SettingsWindowConfigurator: NSViewRepresentable {
  var pane: SettingsPane
  final class Coordinator {
    var configuredWindows = Set<ObjectIdentifier>()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    configureWhenAttached(view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    configureWhenAttached(nsView, coordinator: context.coordinator)
  }

  private func configureWhenAttached(_ view: NSView, coordinator: Coordinator) {
    DispatchQueue.main.async {
      guard let window = view.window else { return }

      window.title = "\(AppBrand.displayName) 设置"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.titlebarSeparatorStyle = .none
      // Keep AppKit's titled-window behavior without a toolbar covering the
      // full-size SwiftUI content at the top of the inset sidebar.
      window.toolbar = nil
      window.styleMask.insert(.fullSizeContentView)
      window.styleMask.insert(.resizable)
      window.styleMask.insert(.titled)
      window.hasShadow = true
      window.isMovableByWindowBackground = true
      window.minSize = NSSize(width: 720, height: 600)
      window.isOpaque = false
      window.backgroundColor = .clear

      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true

      let identifier = ObjectIdentifier(window)
      if coordinator.configuredWindows.insert(identifier).inserted {
        window.setContentSize(NSSize(width: 760, height: 660))
        window.center()
      }
    }
  }
}

/// The same AppKit controls as a titled window, positioned in the inset sidebar.
private struct SettingsTrafficLights: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    let buttons: [(NSWindow.ButtonType, Selector)] = [
      (.closeButton, #selector(NSWindow.performClose(_:))),
      (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
      (.zoomButton, #selector(NSWindow.performZoom(_:))),
    ]
    for (index, item) in buttons.enumerated() {
      guard let button = NSWindow.standardWindowButton(item.0, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
      button.setFrameOrigin(NSPoint(x: index * 23, y: 1))
      button.action = item.1
      view.addSubview(button)
    }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async {
      for case let button as NSButton in view.subviews { button.target = view.window }
    }
  }
}

private struct SettingsChoiceSurface: ViewModifier {
  let tint: Color
  let isSelected: Bool

  func body(content: Content) -> some View {
    content
      .background(isSelected ? tint.opacity(0.08) : Color.primary.opacity(0.025),
                  in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isSelected ? tint.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 0.75)
      }
  }
}

/// Ask AppKit for the installed System Settings extension's icon. This keeps
/// the system's actual artwork and rendering instead of redrawing its symbols.
private struct SettingsSystemIcon: View {
  enum Kind: String, CaseIterable {
    case general, monitoring, keyboard, display, appearance, network, login, update, about, sync

    var path: String {
      let root = "/System/Library/ExtensionKit/Extensions/"
      switch self {
      case .general: return "/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex"
      case .monitoring: return root + "ControlCenterSettings.appex"
      case .keyboard: return root + "KeyboardSettings.appex"
      case .display: return root + "DisplaysExt.appex"
      case .appearance: return root + "Appearance.appex"
      case .network: return root + "Network.appex"
      case .login: return root + "LoginItems.appex"
      case .update: return root + "SoftwareUpdateSettingsExtension.appex"
      case .about: return root + "AboutExtension.appex"
      case .sync: return root + "DateAndTime Extension.appex"
      }
    }

    var fallback: String {
      switch self {
      case .general: return "gear"
      case .monitoring: return "switch.2"
      case .keyboard: return "keyboard"
      case .display: return "sun.max.fill"
      case .appearance: return "circle.lefthalf.filled"
      case .network: return "network"
      case .login: return "list.bullet"
      case .update: return "gear.badge"
      case .about: return "laptopcomputer"
      case .sync: return "clock"
      }
    }

    static func forSymbol(_ symbol: String) -> Kind {
      switch symbol {
      case "keyboard", "keyboard.badge.ellipsis": return .keyboard
      case "rectangle.2.swap", "slider.horizontal.3": return .display
      case "paintpalette", "rectangle.3.group": return .appearance
      case "network", "checkmark.circle.fill", "exclamationmark.triangle.fill": return .network
      case "power": return .login
      case "arrow.triangle.2.circlepath": return .update
      case "info.circle": return .about
      case "clock.arrow.trianglehead.counterclockwise.rotate.90": return .sync
      default: return .monitoring
      }
    }
  }

  let kind: Kind
  let size: CGFloat

  private static let images: [Kind: NSImage] = Dictionary(uniqueKeysWithValues:
    Kind.allCases.compactMap { kind in
      guard FileManager.default.fileExists(atPath: kind.path) else { return nil }
      return (kind, NSWorkspace.shared.icon(forFile: kind.path))
    })

  var body: some View {
    if let image = Self.images[kind] {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .frame(width: size * 1.18, height: size * 1.18)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      Image(systemName: kind.fallback)
        .font(.system(size: size * 0.65))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: size * 0.24))
        .accessibilityHidden(true)
    }
  }
}

/// An owned child panel keeps the preview outside the settings canvas while
/// AppKit handles window ordering, Spaces, and moving the two windows together.
private struct SettingsPreviewCompanion: NSViewRepresentable {
  let isPresented: Bool
  let content: AnyView

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.didAttach = { [weak coordinator = context.coordinator] window in
      coordinator?.attach(to: window)
    }
    return view
  }

  func updateNSView(_ view: AnchorView, context: Context) {
    context.coordinator.isPresented = isPresented
    context.coordinator.update(content: content)
    DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
      coordinator?.attach(to: view?.window)
      coordinator?.synchronize()
    }
  }

  static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
    view.didAttach = nil
    coordinator.detach()
  }

  final class AnchorView: NSView {
    var didAttach: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      didAttach?(window)
    }
  }

  final class Coordinator {
    var isPresented = false
    private weak var owner: NSWindow?
    private var observations: [NSObjectProtocol] = []
    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
      panel = NSPanel(contentRect: .zero,
                      styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
      panel.title = "键盘预览"
      panel.isReleasedWhenClosed = false
      panel.isFloatingPanel = false
      panel.hidesOnDeactivate = false
      panel.isExcludedFromWindowsMenu = true
      panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = true
      panel.contentView = hosting
      hosting.wantsLayer = true
      hosting.layer?.cornerRadius = 12
      hosting.layer?.cornerCurve = .continuous
      hosting.layer?.masksToBounds = true
    }

    func update(content: AnyView) {
      hosting.rootView = content
    }

    func attach(to window: NSWindow?) {
      guard owner !== window else { return }
      detach()
      owner = window
      guard let window else { return }
      let center = NotificationCenter.default
      for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                   NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification,
                   NSWindow.didDeminiaturizeNotification] {
        observations.append(center.addObserver(forName: name, object: window, queue: .main) {
          [weak self] _ in self?.synchronize()
        })
      }
      for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
        observations.append(center.addObserver(forName: name, object: window, queue: .main) {
          [weak self] _ in self?.hide()
        })
      }
      synchronize()
    }

    func synchronize() {
      guard isPresented, let owner, owner.isVisible, !owner.isMiniaturized else {
        hide()
        return
      }
      let size = NSSize(width: 188, height: max(1, hosting.fittingSize.height))
      let screen = owner.screen?.visibleFrame ?? owner.frame.insetBy(dx: -220, dy: -20)
      panel.setFrame(SettingsPreviewPlacement.frame(owner: owner.frame, size: size, screen: screen), display: true)
      panel.appearance = owner.effectiveAppearance
      if panel.parent !== owner { owner.addChildWindow(panel, ordered: .above) }
      if !panel.isVisible { panel.orderFront(nil) }
    }

    private func hide() {
      panel.parent?.removeChildWindow(panel)
      panel.orderOut(nil)
    }

    func detach() {
      hide()
      observations.forEach(NotificationCenter.default.removeObserver)
      observations.removeAll()
      owner = nil
    }

    deinit {
      observations.forEach(NotificationCenter.default.removeObserver)
    }
  }
}

enum SettingsPreviewPlacement {
  static func frame(owner: NSRect, size: NSSize, screen: NSRect) -> NSRect {
    let gap: CGFloat = 12
    let right = owner.maxX + gap
    let left = owner.minX - gap - size.width
    // Prefer the requested right side; use the left only at a screen edge.
    let x = right + size.width <= screen.maxX ? right : max(screen.minX, left)
    let y = max(screen.minY, min(owner.maxY - 52 - size.height, screen.maxY - size.height))
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
  }
}
