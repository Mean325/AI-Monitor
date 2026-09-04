import SwiftUI

struct GrokCardView: View {
  let snapshot: GrokUsageSnapshot?
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat
  let colorScheme: UsageCardColorScheme
  let design: UsageCardDesign

  private var palette: UsageCardPalette { colorScheme.palette }
  private var remainingProgress: CGFloat {
    CGFloat(snapshot?.remainingProgress ?? 0)
  }
  private var remainingText: String {
    snapshot.map { "\($0.remainingPercent)" } ?? "--"
  }
  private var layoutWidth: CGFloat {
    design.usesFullCanvas ? UsageCardLayout.width : 124
  }
  private var layoutHeight: CGFloat {
    if design.usesFullCanvas {
      return UsageCardLayout.height
    }
    return max(320, UsageCardLayout.height - safeAreaHeight - 10)
  }
  private var layoutTopPadding: CGFloat {
    design.usesFullCanvas ? 0 : safeAreaHeight + 1
  }
  private var backgroundColor: Color {
    if design == .minimalColumn { return chronosSurface }
    if design == .nothingMatrix { return palette.background }
    return palette.background
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
        colors: [palette.accent.opacity(0.15), .clear],
        center: .center,
        startRadius: 4,
        endRadius: 130
      )
    case .liquidGlass:
      ZStack {
        Circle()
          .fill(palette.accent.opacity(0.18))
          .frame(width: 130, height: 130)
          .blur(radius: 24)
          .offset(x: 52, y: 92)
        Circle()
          .fill(palette.primaryText.opacity(0.09))
          .frame(width: 110, height: 110)
          .blur(radius: 28)
          .offset(x: -50, y: 300)
      }
    case .commandDeck:
      LinearGradient(
        colors: [palette.accent.opacity(0.10), .clear, palette.accent.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .minimalColumn:
      LinearGradient(
        colors: [chronosPrimary.opacity(0.05), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
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
    case .orbitalRings:
      orbitalRingsLayout
    case .liquidGlass:
      liquidGlassLayout
    case .commandDeck:
      commandDeckLayout
    case .minimalColumn:
      minimalColumnLayout
    case .nothingMatrix:
      nothingMatrixLayout
    }
  }

  private var nothingMatrixLayout: some View {
    NothingUsageCardView(
      palette: palette,
      service: "GROK",
      primaryTitle: snapshot?.windowTitle ?? "周期剩余",
      primaryValue: remainingText,
      primarySuffix: "%",
      primaryCaption: snapshot == nil ? "等待余量同步" : snapshot?.windowDescription ?? "",
      progress: remainingProgress,
      firstMetricTitle: "当前套餐",
      firstMetricValue: snapshot?.compactPlanName ?? "--",
      secondMetricTitle: (snapshot?.prepaidBalance ?? 0) > 0 ? "预付余额" : nil,
      secondMetricValue: (snapshot?.prepaidBalance ?? 0) > 0
        ? "\(snapshot?.prepaidBalance ?? 0)" : nil,
      noticeTitle: "周期重置",
      noticeValue: resetDateText,
      footerTitle: "下次重置",
      footerValue: "\(resetDateText)  \(resetTimeText)",
      activityState: activityState,
      safeAreaHeight: safeAreaHeight
    )
  }

  private var classicLayout: some View {
    VStack(spacing: 0) {
      header.frame(height: 38)
      Rectangle().fill(palette.border).frame(height: 1).padding(.horizontal, 9)
      remainingSection.frame(height: 112)
      planCard
        .frame(width: 106, height: 70)
        .padding(.top, 12)
      Spacer(minLength: 16)
      resetSection.padding(.bottom, 16)
    }
  }

  private var header: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(palette.accent)
        .frame(width: 8, height: 8)
      Text("GROK")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
      Spacer(minLength: 2)
      Text(snapshot == nil ? "等待" : "实时")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(snapshot == nil ? palette.tertiaryText : palette.accent)
    }
    .padding(.horizontal, 9)
  }

  private var remainingSection: some View {
    VStack(spacing: 0) {
      Text(snapshot?.windowTitle ?? "等待同步")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(palette.secondaryText)
        .padding(.top, 11)

      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(remainingText)
          .font(.system(size: 41, weight: .bold, design: .rounded))
          .foregroundStyle(palette.primaryText)
        Text("%")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(palette.accent)
      }
      .frame(height: 50)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(palette.border)
          Capsule()
            .fill(palette.accent)
            .frame(width: proxy.size.width * remainingProgress)
        }
      }
      .frame(width: 106, height: 8)

      Text(snapshot?.windowDescription ?? "尚无数据")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(palette.tertiaryText)
        .padding(.top, 7)
    }
  }

  private var planCard: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(palette.insetBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(palette.border, lineWidth: 1)
        }
      VStack(alignment: .leading, spacing: 4) {
        Text("当前套餐")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.secondaryText)
        Text(snapshot?.planDisplayName ?? "--")
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var resetSection: some View {
    VStack(spacing: 5) {
      Text("下次重置")
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(palette.tertiaryText)
      Text(resetDateText)
        .font(.system(size: 19, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
      Text(resetTimeText)
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(palette.accent)
    }
  }

  private var orbitalRingsLayout: some View {
    VStack(spacing: 0) {
      compactHeader(label: "LEFT")
        .frame(height: 32)
      Text(snapshot?.windowTitle.uppercased() ?? "等待同步")
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .tracking(1.2)
        .foregroundStyle(palette.secondaryText)
        .padding(.top, 8)

      ZStack {
        Circle()
          .stroke(palette.accent.opacity(0.12), lineWidth: 1)
          .frame(width: 116, height: 116)
        Circle()
          .stroke(palette.border.opacity(0.75), style: StrokeStyle(lineWidth: 10, lineCap: .round))
          .frame(width: 98, height: 98)
        Circle()
          .trim(from: 0, to: remainingProgress)
          .stroke(
            AngularGradient(
              colors: [palette.accent.opacity(0.45), palette.accent, palette.primaryText],
              center: .center
            ),
            style: StrokeStyle(lineWidth: 10, lineCap: .round)
          )
          .frame(width: 98, height: 98)
          .rotationEffect(.degrees(-90))
        Circle()
          .fill(palette.cardBackground.opacity(0.72))
          .frame(width: 72, height: 72)
        VStack(spacing: -1) {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(remainingText)
              .font(.system(size: 31, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("%")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(palette.accent)
          }
          Text("剩余")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(palette.tertiaryText)
        }
      }
      .frame(height: 126)

      Text(snapshot?.windowDescription ?? "尚无数据")
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)

      HStack(spacing: 7) {
        orbitalMetricPanel(title: "当前套餐") {
          Text(snapshot?.compactPlanName ?? "--")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        orbitalMetricPanel(title: "下次重置") {
          VStack(spacing: 1) {
            Text(resetDateText)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundStyle(palette.secondaryText)
            Text(resetTimeText)
              .font(.system(size: 16, weight: .bold, design: .rounded))
              .foregroundStyle(palette.accent)
          }
        }
      }
      .frame(height: 76)
      .padding(.horizontal, 5)
      .padding(.top, 13)

      HStack(spacing: 6) {
        Circle().fill(activityColor).frame(width: 8, height: 8)
          .shadow(color: activityColor.opacity(0.55), radius: 4)
        Text(activityState.title)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(snapshot == nil ? "待同步" : "剩余额度")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(snapshot == nil ? palette.tertiaryText : palette.accent)
      }
      .padding(.horizontal, 10)
      .frame(height: 36)
      .background(
        LinearGradient(
          colors: [palette.accent.opacity(0.09), palette.cardBackground.opacity(0.72)],
          startPoint: .leading,
          endPoint: .trailing
        ),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .padding(.horizontal, 5)
      .padding(.top, 14)

      Spacer(minLength: 8)
    }
  }

  private func orbitalMetricPanel<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 5) {
      Text(title)
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)
      content()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      palette.cardBackground.opacity(0.82),
      in: RoundedRectangle(cornerRadius: 15, style: .continuous)
    )
  }

  private var liquidGlassLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "LEFT")
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(
          LinearGradient(
            colors: [palette.primaryText.opacity(0.10), palette.cardBackground.opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          in: Capsule()
        )
        .overlay { Capsule().stroke(palette.primaryText.opacity(0.12), lineWidth: 0.6) }

      glassPanel(cornerRadius: 20) {
        VStack(spacing: 3) {
          Text(snapshot?.windowTitle ?? "等待同步")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(palette.secondaryText)
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(remainingText)
              .font(.system(size: 43, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("%")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(palette.accent)
          }
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule().fill(palette.primaryText.opacity(0.12))
              Capsule()
                .fill(
                  LinearGradient(
                    colors: [palette.accent, palette.primaryText.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: proxy.size.width * remainingProgress)
            }
          }
          .frame(height: 6)
          Text("剩余额度 · \(snapshot?.windowDescription ?? "当前周期")")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(palette.tertiaryText)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .frame(height: 123)

      glassPanel(cornerRadius: 17) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("当前套餐")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(palette.secondaryText)
            Text("剩余用量")
              .font(.system(size: 7, weight: .medium))
              .foregroundStyle(palette.tertiaryText)
          }
          Spacer()
          Text(snapshot?.compactPlanName ?? "--")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
      }
      .frame(height: 68)

      glassPanel(cornerRadius: 17) {
        VStack(spacing: 4) {
          Text("下次重置")
            .font(.system(size: 8, weight: .semibold))
            .tracking(1)
            .foregroundStyle(palette.tertiaryText)
          Text(resetDateText)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)
          Text(resetTimeText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(palette.accent)
        }
      }
      .frame(height: 89)

      Spacer(minLength: 0)
    }
  }

  private func glassPanel<Content: View>(
    cornerRadius: CGFloat,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return content()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        shape.fill(
          LinearGradient(
            colors: [
              palette.primaryText.opacity(0.11),
              palette.cardBackground.opacity(0.76),
              palette.accent.opacity(0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
      .overlay {
        shape.stroke(
          LinearGradient(
            colors: [palette.primaryText.opacity(0.22), palette.border.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 0.7
        )
      }
      .shadow(color: palette.accent.opacity(0.09), radius: 12, y: 6)
  }

  private var commandDeckLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "LEFT")
        .frame(height: 30)
      VStack(alignment: .leading, spacing: 5) {
        Text(snapshot?.windowTitle.uppercased() ?? "周期剩余")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(1)
          .foregroundStyle(palette.secondaryText)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(remainingText)
            .font(.system(size: 45, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          Text(snapshot == nil ? "" : "% 剩余")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(palette.accent)
            .lineLimit(1)
        }
        Text(snapshot?.windowDescription ?? "尚无数据")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(palette.tertiaryText)
          .lineLimit(1)
        Spacer(minLength: 2)
        GeometryReader { proxy in
          HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
              Capsule()
                .fill(CGFloat(index) / 10 < remainingProgress ? palette.accent : palette.border)
                .frame(width: max(0, (proxy.size.width - 18) / 10))
            }
          }
        }
        .frame(height: 7)
      }
      .padding(12)
      .frame(height: 124, alignment: .top)
      .background(
        LinearGradient(
          colors: [palette.accent.opacity(0.11), palette.cardBackground.opacity(0.88)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )

      HStack(spacing: 7) {
        commandMetric(title: "当前套餐", value: snapshot?.compactPlanName ?? "--")
        commandMetric(title: "重置日期", value: resetDateText)
      }
      .frame(height: 68)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("下次重置")
            .font(.system(size: 9, weight: .semibold))
          Spacer()
          Circle().fill(activityColor).frame(width: 6, height: 6)
          Text(activityState.title)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(activityColor)
        }
        .foregroundStyle(palette.tertiaryText)
        Text(resetTimeText)
          .font(.system(size: 22, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.accent)
      }
      .padding(.horizontal, 12)
      .frame(height: 78)
      .background(
        palette.cardBackground.opacity(0.78),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )

      Spacer(minLength: 0)
    }
  }

  private func commandMetric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)
      Text(value)
        .font(.system(size: value.count > 4 ? 12 : 18, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      palette.cardBackground.opacity(0.74),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
  }

  private var minimalColumnLayout: some View {
    HStack(spacing: 0) {
      GeometryReader { proxy in
        ZStack(alignment: .bottom) {
          chronosSurfaceHighest
          Capsule()
            .fill(palette.accent)
            .frame(
              width: 6,
              height: max(6, proxy.size.height * remainingProgress + 6)
            )
            .offset(y: 3)
            .shadow(color: palette.accent.opacity(0.55), radius: 7)
        }
        .clipped()
      }
      .frame(width: 6)

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("GROK")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1)
            .foregroundStyle(chronosOnSurface)
          HStack(spacing: 5) {
            ZStack {
              Circle().fill(activityColor.opacity(0.18)).frame(width: 14, height: 14)
              Circle().fill(activityColor).frame(width: 8, height: 8)
            }
            .shadow(color: activityColor.opacity(0.75), radius: 4)
            Text(activityState.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(chronosOnSurfaceVariant)
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .leading, spacing: 3) {
          Text(snapshot?.windowTitle ?? "周期剩余")
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(chronosOnSurfaceVariant)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(remainingText)
              .font(.system(size: 40, weight: .bold, design: .monospaced))
              .tracking(1)
              .foregroundStyle(chronosOnSurface)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
            Text("%")
              .font(.system(size: 16, weight: .bold, design: .monospaced))
              .foregroundStyle(palette.accent)
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("当前套餐")
              .font(.system(size: 10, weight: .medium))
              .tracking(0.4)
              .foregroundStyle(chronosOnSurfaceVariant)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text(snapshot?.planDisplayName ?? "--")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(chronosOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(height: 28, alignment: .bottomLeading)
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            chronosSurfaceLow.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Color.white.opacity(0.05), lineWidth: 1)
          }

          VStack(alignment: .leading, spacing: 3) {
            Text("重置时间")
              .font(.system(size: 10, weight: .medium))
              .tracking(0.4)
              .foregroundStyle(chronosOutline)

            Text(resetISODateText)
              .font(.system(size: 13, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface)
              .lineLimit(1)
              .minimumScaleFactor(0.82)

            Text(resetTimeText)
              .font(.system(size: 13, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface.opacity(0.60))
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, safeAreaHeight + 16)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .background(chronosSurface)
  }

  private func compactHeader(label: String) -> some View {
    HStack(spacing: 5) {
      Circle().fill(palette.accent).frame(width: 6, height: 6)
      Text("GROK")
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
      Spacer()
      Text(label)
        .font(.system(size: 7, weight: .bold, design: .monospaced))
        .tracking(0.6)
        .foregroundStyle(palette.tertiaryText)
    }
    .padding(.horizontal, 9)
  }

  private var resetDateText: String {
    guard let date = snapshot?.periodEnd else { return "--月--日" }
    return Self.dateFormatter.string(from: date)
  }

  private var resetISODateText: String {
    guard let date = snapshot?.periodEnd else { return "----/--/--" }
    return Self.isoDateFormatter.string(from: date)
  }

  private var resetTimeText: String {
    guard let date = snapshot?.periodEnd else { return "--:--" }
    return Self.timeFormatter.string(from: date)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter
  }()

  private var chronosPrimary: Color {
    Color(red: 0, green: 240 / 255, blue: 1)
  }
  private var chronosSurface: Color {
    Color(red: 19 / 255, green: 19 / 255, blue: 19 / 255)
  }
  private var chronosSurfaceLow: Color {
    Color(red: 28 / 255, green: 27 / 255, blue: 27 / 255)
  }
  private var chronosSurfaceHighest: Color {
    Color(red: 53 / 255, green: 53 / 255, blue: 52 / 255)
  }
  private var chronosOnSurface: Color {
    Color(red: 229 / 255, green: 226 / 255, blue: 225 / 255)
  }
  private var chronosOnSurfaceVariant: Color {
    Color(red: 185 / 255, green: 202 / 255, blue: 203 / 255)
  }
  private var chronosOutline: Color {
    Color(red: 132 / 255, green: 148 / 255, blue: 149 / 255)
  }
}
