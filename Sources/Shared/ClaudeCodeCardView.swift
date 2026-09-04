import SwiftUI

struct ClaudeCodeCardView: View {
  let snapshot: ClaudeCodeUsageSnapshot?
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat
  let colorScheme: UsageCardColorScheme
  let design: UsageCardDesign

  private var palette: UsageCardPalette { colorScheme.palette }
  private var layoutWidth: CGFloat { design.usesFullCanvas ? UsageCardLayout.width : 124 }
  private var layoutHeight: CGFloat {
    design.usesFullCanvas
      ? UsageCardLayout.height
      : max(320, UsageCardLayout.height - safeAreaHeight - 10)
  }
  private var layoutTopPadding: CGFloat { design.usesFullCanvas ? 0 : safeAreaHeight + 1 }
  private var backgroundColor: Color {
    if design == .minimalColumn { return chronosSurface }
    if design == .nothingMatrix { return palette.background }
    return palette.background
  }

  private var todayTokens: Int { snapshot?.todayTokens ?? 0 }
  private var weekTokens: Int { snapshot?.weekTokens ?? 0 }
  private var todayRatio: CGFloat {
    guard weekTokens > 0 else { return 0 }
    return CGFloat(max(0, min(todayTokens, weekTokens))) / CGFloat(weekTokens)
  }
  private var percentageValue: Int { Int(round(todayRatio * 100)) }
  private var todayText: String {
    snapshot.map { ClaudeCodeTokenFormatter.string(from: $0.todayTokens) } ?? "--"
  }
  private var weekText: String {
    snapshot.map { ClaudeCodeTokenFormatter.string(from: $0.weekTokens) } ?? "--"
  }
  private var activityColor: Color {
    switch activityState {
    case .idle, .finished:
      return Color(red: 51 / 255, green: 199 / 255, blue: 110 / 255)
    case .running:
      return Color(red: 255 / 255, green: 199 / 255, blue: 31 / 255)
    case .awaitingAuthorization, .toolFailed:
      return Color(red: 242 / 255, green: 56 / 255, blue: 64 / 255)
    }
  }

  var body: some View {
    ZStack(alignment: .top) {
      backgroundColor
      designBackdrop
      selectedLayout
        .frame(width: layoutWidth, height: layoutHeight)
        .padding(.top, layoutTopPadding)
    }
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .clipped()
  }

  @ViewBuilder
  private var designBackdrop: some View {
    switch design {
    case .classic:
      EmptyView()
    case .orbitalRings:
      RadialGradient(
        colors: [palette.accent.opacity(0.15), .clear], center: .center,
        startRadius: 4, endRadius: 130)
    case .liquidGlass:
      ZStack {
        Circle().fill(palette.accent.opacity(0.18)).frame(width: 130, height: 130)
          .blur(radius: 24).offset(x: 52, y: 92)
        Circle().fill(palette.primaryText.opacity(0.09)).frame(width: 110, height: 110)
          .blur(radius: 28).offset(x: -50, y: 300)
      }
    case .commandDeck:
      LinearGradient(
        colors: [palette.accent.opacity(0.10), .clear, palette.accent.opacity(0.04)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    case .minimalColumn:
      LinearGradient(
        colors: [chronosPrimary.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)
    case .nothingMatrix:
      EmptyView()
    }
  }

  @ViewBuilder
  private var selectedLayout: some View {
    switch design {
    case .classic:
      classicLayout
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(palette.border, lineWidth: 1)
        }
    case .orbitalRings: orbitalRingsLayout
    case .liquidGlass: liquidGlassLayout
    case .commandDeck: commandDeckLayout
    case .minimalColumn: minimalColumnLayout
    case .nothingMatrix: nothingMatrixLayout
    }
  }

  private var nothingMatrixLayout: some View {
    NothingUsageCardView(
      palette: palette,
      service: "CLAUDE",
      primaryTitle: "今日 Token",
      primaryValue: todayText,
      primarySuffix: "tok",
      primaryCaption: "近 7 天  \(weekText) token",
      progress: todayRatio,
      firstMetricTitle: "今日会话",
      firstMetricValue: snapshot.map { "\($0.todaySessions) 个" } ?? "--",
      secondMetricTitle: "当前模型",
      secondMetricValue: nothingModelText,
      noticeTitle: nil,
      noticeValue: nil,
      footerTitle: "最近活跃",
      footerValue: lastActiveText,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight
    )
  }

  private var nothingModelText: String {
    guard let model = snapshot?.modelDisplayName, !model.isEmpty else { return "--" }
    if model == "<synthetic>" { return "SYNTH" }
    return String(model.prefix(8)).uppercased()
  }

  // MARK: - 经典卡片

  private var classicLayout: some View {
    VStack(spacing: 0) {
      header.frame(height: 38)
      Rectangle().fill(palette.border).frame(height: 1).padding(.horizontal, 9)
      todaySection.frame(height: 116)
      sessionsModelRow.frame(height: 66).padding(.top, 12)
      Spacer(minLength: 12)
      bottomSection.padding(.bottom, 14)
    }
    .padding(.horizontal, 9)
  }

  private var header: some View {
    HStack(spacing: 5) {
      Circle().fill(palette.accent).frame(width: 8, height: 8)
      Text("CLAUDE")
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
      Spacer(minLength: 2)
      Text(snapshot == nil ? "等待" : "实时")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(snapshot == nil ? palette.tertiaryText : palette.accent)
    }
  }

  private var todaySection: some View {
    VStack(spacing: 0) {
      Text("今日用量")
        .font(.system(size: 11, weight: .semibold)).tracking(0.8)
        .foregroundStyle(palette.secondaryText).padding(.top, 11)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(todayText)
          .font(.system(size: 38, weight: .bold, design: .rounded))
          .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.7)
        Text("tok").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.accent)
      }
      .frame(height: 50)
      progressBar(height: 8)
      Text("近 7 天 \(weekText)")
        .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.tertiaryText)
        .padding(.top, 7)
    }
  }

  private var sessionsModelRow: some View {
    HStack(spacing: 8) {
      metricCell(title: "今日会话") {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(snapshot.map { "\($0.todaySessions)" } ?? "--")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)
          Text("个").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.accent)
        }
      }
      metricCell(title: "模型") {
        Text(snapshot?.modelDisplayName ?? "--")
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.6)
      }
    }
  }

  // MARK: - 轨道圆环

  private var orbitalRingsLayout: some View {
    VStack(spacing: 0) {
      compactHeader(label: "USAGE").frame(height: 32)
      Text("今日 TOKEN")
        .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
        .foregroundStyle(palette.secondaryText).padding(.top, 8)
      ZStack {
        Circle().stroke(palette.accent.opacity(0.12), lineWidth: 1).frame(width: 116, height: 116)
        Circle().stroke(palette.border.opacity(0.75), style: StrokeStyle(lineWidth: 10, lineCap: .round))
          .frame(width: 98, height: 98)
        Circle().trim(from: 0, to: min(1, todayRatio))
          .stroke(
            AngularGradient(colors: [palette.accent.opacity(0.45), palette.accent, palette.primaryText], center: .center),
            style: StrokeStyle(lineWidth: 10, lineCap: .round))
          .frame(width: 98, height: 98).rotationEffect(.degrees(-90))
        Circle().fill(palette.cardBackground.opacity(0.72)).frame(width: 72, height: 72)
        VStack(spacing: 0) {
          Text(todayText).font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.7)
          Text("\(percentageValue)% / 周")
            .font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.accent)
        }
      }
      .frame(height: 126)
      Text("近 7 天 \(weekText) token")
        .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.tertiaryText)
      HStack(spacing: 7) {
        orbitalMetric(title: "今日会话", value: snapshot.map { "\($0.todaySessions)" } ?? "--")
        orbitalMetric(title: "模型", value: snapshot?.modelDisplayName ?? "--")
      }
      .frame(height: 76).padding(.horizontal, 5).padding(.top, 13)
      statusStrip.padding(.horizontal, 5).padding(.top, 14)
      Spacer(minLength: 8)
      Text(lastActiveText)
        .font(.system(size: 7, weight: .semibold)).tracking(0.5)
        .foregroundStyle(palette.tertiaryText).padding(.bottom, 8)
    }
  }

  private func orbitalMetric(title: String, value: String) -> some View {
    VStack(spacing: 5) {
      Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.tertiaryText)
      Text(value).font(.system(size: value.count > 4 ? 12 : 25, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.65)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15))
  }

  // MARK: - 液态玻璃

  private var liquidGlassLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "LIVE").padding(.horizontal, 7).frame(height: 32)
        .background(
          LinearGradient(colors: [palette.primaryText.opacity(0.10), palette.cardBackground.opacity(0.58)],
            startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
        .overlay { Capsule().stroke(palette.primaryText.opacity(0.12), lineWidth: 0.6) }
      glassPanel(cornerRadius: 20) {
        VStack(spacing: 5) {
          Text("今日 TOKEN").font(.system(size: 9, weight: .semibold)).tracking(0.8)
            .foregroundStyle(palette.secondaryText)
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(todayText).font(.system(size: 40, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.65)
            Text("tok").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.accent)
          }
          progressBar(height: 6)
          Text("近 7 天 \(weekText)").font(.system(size: 8, weight: .medium))
            .foregroundStyle(palette.tertiaryText)
        }.padding(.horizontal, 12)
      }.frame(height: 123)
      glassPanel(cornerRadius: 17) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("今日会话").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.secondaryText)
            Text(activityState.title).font(.system(size: 8, weight: .medium)).foregroundStyle(activityColor)
          }
          Spacer()
          Text(snapshot.map { "\($0.todaySessions)" } ?? "--")
            .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(palette.primaryText)
        }.padding(.horizontal, 12)
      }.frame(height: 68)
      glassPanel(cornerRadius: 17) {
        VStack(spacing: 5) {
          Text("当前模型").font(.system(size: 8, weight: .semibold)).tracking(1)
            .foregroundStyle(palette.tertiaryText)
          Text(snapshot?.modelDisplayName ?? "--")
            .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(palette.accent)
            .lineLimit(1).minimumScaleFactor(0.65)
          Text(lastActiveText).font(.system(size: 9, weight: .medium)).foregroundStyle(palette.tertiaryText)
        }
      }.frame(height: 89)
      Spacer(minLength: 0)
    }
  }

  private func glassPanel<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return content().frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        shape.fill(LinearGradient(
          colors: [palette.primaryText.opacity(0.11), palette.cardBackground.opacity(0.76), palette.accent.opacity(0.06)],
          startPoint: .topLeading, endPoint: .bottomTrailing))
      }
      .overlay {
        shape.stroke(LinearGradient(colors: [palette.primaryText.opacity(0.22), palette.border.opacity(0.22)],
          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
      }
      .shadow(color: palette.accent.opacity(0.09), radius: 12, y: 6)
  }

  // MARK: - 指挥舱

  private var commandDeckLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "DASH").frame(height: 30)
      VStack(alignment: .leading, spacing: 5) {
        Text("TODAY TOKEN").font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(1).foregroundStyle(palette.secondaryText)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(todayText).font(.system(size: 42, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.68)
          Text("tok").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.accent)
        }
        Text("近 7 天 \(weekText)").font(.system(size: 8, weight: .medium)).foregroundStyle(palette.tertiaryText)
        Spacer(minLength: 2)
        segmentedProgress
      }
      .padding(12).frame(height: 124, alignment: .top)
      .background(LinearGradient(colors: [palette.accent.opacity(0.11), palette.cardBackground.opacity(0.88)],
        startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      HStack(spacing: 7) {
        commandMetric(title: "今日会话", value: snapshot.map { "\($0.todaySessions)" } ?? "--")
        commandMetric(title: "模型", value: snapshot?.modelDisplayName ?? "--")
      }.frame(height: 68)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("最近活跃").font(.system(size: 9, weight: .semibold))
          Spacer()
          Circle().fill(activityColor).frame(width: 6, height: 6)
          Text(activityState.title).font(.system(size: 7, weight: .bold)).foregroundStyle(activityColor)
        }.foregroundStyle(palette.tertiaryText)
        Text(lastActiveText).font(.system(size: 18, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.accent).lineLimit(1).minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 12).frame(height: 78)
      .background(palette.cardBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
      Spacer(minLength: 0)
    }
  }

  private func commandMetric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.tertiaryText)
      Text(value).font(.system(size: value.count > 4 ? 11 : 24, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(palette.cardBackground.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
  }

  // MARK: - 简约立柱

  private var minimalColumnLayout: some View {
    HStack(spacing: 0) {
      GeometryReader { proxy in
        ZStack(alignment: .bottom) {
          chronosSurfaceHighest
          Capsule().fill(palette.accent)
            .frame(width: 6, height: max(6, proxy.size.height * min(1, todayRatio) + 6))
            .offset(y: 3).shadow(color: palette.accent.opacity(0.55), radius: 7)
        }.clipped()
      }.frame(width: 6)
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("CLAUDE").font(.system(size: 10, weight: .black, design: .rounded)).tracking(1)
            .foregroundStyle(chronosOnSurface)
          HStack(spacing: 5) {
            ZStack {
              Circle().fill(activityColor.opacity(0.18)).frame(width: 14, height: 14)
              Circle().fill(activityColor).frame(width: 8, height: 8)
            }.shadow(color: activityColor.opacity(0.75), radius: 4)
            Text(activityState.title).font(.system(size: 11, weight: .semibold))
              .foregroundStyle(chronosOnSurfaceVariant)
          }
        }
        Spacer(minLength: 10)
        VStack(alignment: .leading, spacing: 3) {
          Text("今日 TOKEN").font(.system(size: 11, weight: .medium)).tracking(0.5)
            .foregroundStyle(chronosOnSurfaceVariant)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(todayText).font(.system(size: 36, weight: .bold, design: .monospaced)).tracking(1)
              .foregroundStyle(chronosOnSurface).lineLimit(1).minimumScaleFactor(0.68)
            Text("tok").font(.system(size: 11, weight: .bold, design: .monospaced))
              .foregroundStyle(palette.accent)
          }
        }
        Spacer(minLength: 10)
        VStack(alignment: .leading, spacing: 16) {
          chronosMetric(title: "近 7 天", value: weekText, suffix: "tok")
          VStack(alignment: .leading, spacing: 4) {
            Text("会话 / 模型").font(.system(size: 10, weight: .medium)).tracking(0.4)
              .foregroundStyle(chronosOutline)
            Text("\(snapshot.map { "\($0.todaySessions)" } ?? "--") 个")
              .font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundStyle(chronosOnSurface)
            Text(snapshot?.modelDisplayName ?? "--")
              .font(.system(size: 11, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface.opacity(0.72)).lineLimit(1).minimumScaleFactor(0.72)
            Text(lastActiveText).font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface.opacity(0.55))
          }
        }
      }
      .padding(.horizontal, 12).padding(.top, safeAreaHeight + 16).padding(.bottom, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }.background(chronosSurface)
  }

  private func chronosMetric(title: String, value: String, suffix: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.system(size: 10, weight: .medium)).tracking(0.4)
        .foregroundStyle(chronosOnSurfaceVariant)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value).font(.system(size: 25, weight: .semibold, design: .monospaced))
          .foregroundStyle(chronosOnSurface).lineLimit(1).minimumScaleFactor(0.7)
        Text(suffix).font(.system(size: 9, weight: .medium)).foregroundStyle(chronosOutline)
      }
    }
    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    .background(chronosSurfaceLow.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1) }
  }

  // MARK: - 共用组件

  private func metricCell<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondaryText)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.vertical, 8)
    .background(palette.insetBackground, in: RoundedRectangle(cornerRadius: 9))
    .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1) }
  }

  private func compactHeader(label: String) -> some View {
    HStack(spacing: 5) {
      Circle().fill(palette.accent).frame(width: 6, height: 6)
      Text("CLAUDE").font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText).lineLimit(1)
      Spacer()
      Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(0.6)
        .foregroundStyle(palette.tertiaryText)
    }.padding(.horizontal, 9)
  }

  private func progressBar(height: CGFloat) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(palette.border)
        Capsule().fill(palette.accent).frame(width: proxy.size.width * min(1, todayRatio))
      }
    }.frame(height: height)
  }

  private var segmentedProgress: some View {
    GeometryReader { proxy in
      HStack(spacing: 2) {
        ForEach(0..<10, id: \.self) { index in
          Capsule().fill(CGFloat(index) / 10 < todayRatio ? palette.accent : palette.border)
            .frame(width: max(0, (proxy.size.width - 18) / 10))
        }
      }
    }.frame(height: 7)
  }

  private var statusStrip: some View {
    HStack(spacing: 7) {
      Circle().fill(activityColor).frame(width: 8, height: 8)
        .shadow(color: activityColor.opacity(0.6), radius: 4)
      VStack(alignment: .leading, spacing: 1) {
        Text("任务状态").font(.system(size: 7, weight: .medium)).foregroundStyle(palette.tertiaryText)
        Text(activityState.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.primaryText)
      }
      Spacer()
      Text(snapshot == nil ? "等待同步" : "实时更新")
        .font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.accent)
    }
    .padding(.horizontal, 10).frame(height: 36)
    .background(LinearGradient(colors: [palette.accent.opacity(0.09), palette.cardBackground.opacity(0.72)],
      startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
  }

  private var bottomSection: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Circle().fill(activityColor).frame(width: 8, height: 8)
          .shadow(color: activityColor.opacity(0.6), radius: 4)
        Text(activityState.title).font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.secondaryText)
        Spacer(minLength: 0)
      }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("最近活跃").font(.system(size: 10, weight: .medium)).foregroundStyle(palette.tertiaryText)
        Spacer(minLength: 0)
        Text(lastActiveText).font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(palette.primaryText)
      }
    }
  }

  private var lastActiveText: String {
    guard let date = snapshot?.lastActiveDate else { return "尚无记录" }
    return "\(Self.dateFormatter.string(from: date)) \(Self.timeFormatter.string(from: date))"
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"; return formatter
  }()
  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"; return formatter
  }()

  private var chronosPrimary: Color { Color(red: 0, green: 240 / 255, blue: 1) }
  private var chronosSurface: Color { Color(red: 19 / 255, green: 19 / 255, blue: 19 / 255) }
  private var chronosSurfaceLow: Color { Color(red: 28 / 255, green: 27 / 255, blue: 27 / 255) }
  private var chronosSurfaceHighest: Color { Color(red: 53 / 255, green: 53 / 255, blue: 52 / 255) }
  private var chronosOnSurface: Color { Color(red: 229 / 255, green: 226 / 255, blue: 225 / 255) }
  private var chronosOnSurfaceVariant: Color { Color(red: 185 / 255, green: 202 / 255, blue: 203 / 255) }
  private var chronosOutline: Color { Color(red: 132 / 255, green: 148 / 255, blue: 149 / 255) }
}
