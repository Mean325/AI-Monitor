import SwiftUI

struct QoderCardView: View {
  let snapshot: QoderUsageSnapshot?
  let creditSnapshot: QoderCreditSnapshot?
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat
  let colorScheme: UsageCardColorScheme
  let design: UsageCardDesign

  private var palette: UsageCardPalette {
    colorScheme.palette(remainingPercent: creditSnapshot?.remainingPercent)
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

  private var creditUsed: Int { creditSnapshot?.creditsUsed ?? 0 }
  private var creditTotal: Int { creditSnapshot?.creditsTotal ?? 0 }
  private var creditRemaining: Int { creditSnapshot?.creditsRemaining ?? 0 }
  private var creditPercentage: CGFloat {
    guard let credit = creditSnapshot, credit.creditsTotal > 0 else { return 0 }
    return CGFloat(credit.usagePercentage)
  }
  private var creditPercentageText: String {
    guard let credit = creditSnapshot, credit.hasData else { return "--" }
    return "\(Int(round(credit.usagePercentage * 100)))"
  }
  private var creditPercentageSuffix: String {
    creditSnapshot?.hasData == true ? "%" : ""
  }
  private var creditSummaryText: String {
    guard creditSnapshot?.hasData == true else { return "额度数据待同步" }
    return "已用 \(Self.compactCount(creditUsed)) / 总计 \(Self.compactCount(creditTotal))"
  }
  private var todayPromptsText: String {
    snapshot.map { Self.compactCount($0.todayPrompts) } ?? "--"
  }
  private var weekPromptsText: String {
    snapshot.map { Self.compactCount($0.weekPrompts) } ?? "--"
  }
  private var contextPercentageText: String {
    guard let credit = creditSnapshot, credit.contextLimitTokens > 0 else { return "--" }
    return credit.contextPercentageDisplay
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
      service: "QODER",
      primaryTitle: "Credit 已用",
      primaryValue: creditPercentageText,
      primarySuffix: creditPercentageSuffix,
      primaryCaption: creditSummaryText,
      progress: creditPercentage,
      firstMetricTitle: "今日对话",
      firstMetricValue: "\(todayPromptsText) 次",
      secondMetricTitle: "上下文",
      secondMetricValue: contextPercentageText,
      noticeTitle: nil,
      noticeValue: nil,
      footerTitle: "最近活跃",
      footerValue: lastActiveText,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight
    )
  }

  // MARK: - 经典卡片

  private var classicLayout: some View {
    VStack(spacing: 0) {
      header
        .frame(height: 38)

      Rectangle()
        .fill(palette.border)
        .frame(height: 1)
        .padding(.horizontal, 9)

      creditMainSection
        .frame(height: 116)

      todayAndContextRow
        .padding(.top, 10)

      Spacer(minLength: 8)

      bottomSection
        .padding(.bottom, 14)
    }
    .padding(.horizontal, 9)
  }

  private var header: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(palette.accent)
        .frame(width: 8, height: 8)

      Text("QODER")
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)

      Spacer(minLength: 2)

      Text(snapshot == nil ? "等待" : "实时")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(snapshot == nil ? palette.tertiaryText : palette.accent)
    }
  }

  private var creditMainSection: some View {
    VStack(spacing: 0) {
      Text("Credit 额度")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(palette.secondaryText)
        .padding(.top, 11)

      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(creditPercentageText)
          .font(.system(size: 38, weight: .bold, design: .rounded))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(creditPercentageSuffix)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(palette.accent)
      }
      .frame(height: 50)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(palette.border)
          Capsule()
            .fill(
              (creditSnapshot?.isQuotaExceeded == true)
                ? Color(red: 242 / 255, green: 56 / 255, blue: 64 / 255)
                : palette.accent
            )
            .frame(width: proxy.size.width * min(1, creditPercentage))
        }
      }
      .frame(height: 8)

      HStack(spacing: 4) {
        Text(creditSummaryText)
        Spacer(minLength: 2)
        if creditSnapshot?.hasData == true {
          Text("余 \(Self.compactCount(creditRemaining))")
        }
      }
      .font(.system(size: 8, weight: .medium))
      .foregroundStyle(palette.tertiaryText)
      .lineLimit(1)
      .padding(.top, 7)
    }
  }

  private var todayAndContextRow: some View {
    HStack(spacing: 8) {
      metricCell(title: "今日对话") {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(todayPromptsText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)
          Text("次")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(palette.accent)
        }
      }

      if let credit = creditSnapshot, credit.contextLimitTokens > 0 {
        metricCell(title: "上下文") {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(credit.contextPercentageDisplay)
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
          }
        }
      } else {
        metricCell(title: "近 7 天") {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(weekPromptsText)
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("次")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(palette.accent)
          }
        }
      }
    }
  }

  private func metricCell<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(palette.secondaryText)
        .lineLimit(1)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 6)
    .padding(.vertical, 8)
    .background(palette.insetBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(palette.border, lineWidth: 1)
    }
  }

  private var bottomSection: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Circle()
          .fill(activityColor)
          .frame(width: 8, height: 8)
          .shadow(color: activityColor.opacity(0.6), radius: 4)

        Text(activityState.title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.secondaryText)

        Spacer(minLength: 0)
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("最近活跃")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(palette.tertiaryText)
        Spacer(minLength: 0)
        Text(lastActiveText)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(palette.primaryText)
      }
    }
  }

  // MARK: - 轨道圆环

  private var orbitalRingsLayout: some View {
    VStack(spacing: 0) {
      compactHeader(label: "LIVE")
        .frame(height: 32)

      Text("CREDIT 额度")
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
          .trim(from: 0, to: min(1, creditPercentage))
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
          .overlay {
            Circle().stroke(palette.primaryText.opacity(0.08), lineWidth: 1)
          }

        VStack(spacing: -1) {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(creditPercentageText)
              .font(.system(size: 31, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text(creditPercentageSuffix)
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(palette.accent)
          }
          Text("已用")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(palette.tertiaryText)
        }
      }
      .frame(height: 126)

      Text(creditSummaryText)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)

      HStack(spacing: 7) {
        orbitalMetricPanel(title: "今日对话") {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(todayPromptsText)
              .font(.system(size: 27, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("次")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(palette.accent)
          }
        }

        orbitalMetricPanel(title: "上下文") {
          VStack(spacing: 1) {
            Text(contextPercentageText)
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
          .fixedSize(horizontal: true, vertical: false)

        Spacer(minLength: 0)

        Text(snapshot == nil ? "待同步" : "实时")
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

      HStack(alignment: .top, spacing: 6) {
        Capsule()
          .fill(palette.accent.opacity(0.24))
          .frame(width: 18, height: 1)
        Text(lastActiveText)
          .font(.system(size: 7, weight: .semibold))
          .tracking(0.5)
          .foregroundStyle(palette.tertiaryText)
        Capsule()
          .fill(palette.accent.opacity(0.24))
          .frame(width: 18, height: 1)
      }
      .padding(.bottom, 8)
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

  // MARK: - 液态玻璃

  private var liquidGlassLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "LIVE")
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
          Text("Credit 额度")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(palette.secondaryText)

          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(creditPercentageText)
              .font(.system(size: 43, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text(creditPercentageSuffix)
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
                .frame(width: proxy.size.width * min(1, creditPercentage))
            }
          }
          .frame(height: 6)

          Text(creditSummaryText)
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
            Text("今日对话")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(palette.secondaryText)
            HStack(spacing: 4) {
              Circle().fill(activityColor).frame(width: 6, height: 6)
              Text(activityState.title)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(activityColor)
            }
          }
          Spacer()
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(todayPromptsText)
              .font(.system(size: 28, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("次")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(palette.accent)
          }
        }
        .padding(.horizontal, 12)
      }
      .frame(height: 68)

      glassPanel(cornerRadius: 17) {
        VStack(spacing: 4) {
          Text("上下文占用")
            .font(.system(size: 8, weight: .semibold))
            .tracking(1)
            .foregroundStyle(palette.tertiaryText)
          Text(contextPercentageText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(palette.accent)
          Text(lastActiveText)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(palette.tertiaryText)
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

  // MARK: - 指挥舱

  private var commandDeckLayout: some View {
    VStack(spacing: 8) {
      compactHeader(label: "DASH")
        .frame(height: 30)

      VStack(alignment: .leading, spacing: 5) {
        Text("CREDIT 额度")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(1)
          .foregroundStyle(palette.secondaryText)

        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(creditPercentageText)
            .font(.system(size: 45, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .layoutPriority(1)
          Text(creditSnapshot?.hasData == true ? "% 已用" : "")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(palette.accent)
            .lineLimit(1)
        }

        Text(creditSummaryText)
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(palette.tertiaryText)
          .lineLimit(1)

        Spacer(minLength: 2)

        GeometryReader { proxy in
          HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
              Capsule()
                .fill(CGFloat(index) / 10 < creditPercentage ? palette.accent : palette.border)
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
        commandMetric(
          title: "今日对话",
          value: todayPromptsText,
          suffix: "次"
        )
        commandMetric(
          title: "上下文",
          value: contextPercentageText,
          suffix: ""
        )
      }
      .frame(height: 68)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("最近活跃")
            .font(.system(size: 9, weight: .semibold))
          Spacer()
          Circle()
            .fill(activityColor)
            .frame(width: 6, height: 6)
          Text(activityState.title)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(activityColor)
        }
        .foregroundStyle(palette.tertiaryText)

        Text(lastActiveText)
          .font(.system(size: 11, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.accent)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
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

  private func commandMetric(title: String, value: String, suffix: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(value)
          .font(.system(size: value.count > 3 ? 10 : 24, weight: .bold, design: .rounded))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Text(suffix)
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(palette.accent)
      }
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      palette.cardBackground.opacity(0.74),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
  }

  // MARK: - 简约立柱

  private var minimalColumnLayout: some View {
    HStack(spacing: 0) {
      GeometryReader { proxy in
        ZStack(alignment: .bottom) {
          chronosSurfaceHighest

          Capsule()
            .fill(palette.accent)
            .frame(
              width: 6,
              height: max(6, proxy.size.height * min(1, creditPercentage) + 6)
            )
            .offset(y: 3)
            .shadow(color: palette.accent.opacity(0.55), radius: 7)
        }
        .clipped()
      }
      .frame(width: 6)

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("QODER")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1)
            .foregroundStyle(chronosOnSurface)

          HStack(spacing: 5) {
            ZStack {
              Circle()
                .fill(activityColor.opacity(0.18))
                .frame(width: 14, height: 14)

              Circle()
                .fill(activityColor)
                .frame(width: 8, height: 8)
            }
            .shadow(color: activityColor.opacity(0.75), radius: 4)

            Text(activityState.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(chronosOnSurfaceVariant)
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .leading, spacing: 3) {
          Text("Credit 额度")
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(chronosOnSurfaceVariant)

          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(creditPercentageText)
              .font(.system(size: 40, weight: .bold, design: .monospaced))
              .tracking(1)
              .foregroundStyle(chronosOnSurface)
              .lineLimit(1)
              .minimumScaleFactor(0.78)

            Text(creditPercentageSuffix)
              .font(.system(size: 16, weight: .bold, design: .monospaced))
              .foregroundStyle(palette.accent)
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("今日对话")
              .font(.system(size: 10, weight: .medium))
              .tracking(0.4)
              .foregroundStyle(chronosOnSurfaceVariant)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text(todayPromptsText)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundStyle(chronosOnSurface)
              Text("次")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(chronosOutline)
            }
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
            Text("上下文占用")
              .font(.system(size: 10, weight: .medium))
              .tracking(0.4)
              .foregroundStyle(chronosOutline)

            Text(contextPercentageText)
              .font(.system(size: 13, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface)
              .lineLimit(1)
              .minimumScaleFactor(0.82)

            Text(lastActiveText)
              .font(.system(size: 11, weight: .medium, design: .monospaced))
              .foregroundStyle(chronosOnSurface.opacity(0.60))
              .lineLimit(1)
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

  // MARK: - 共用组件

  private func compactHeader(label: String) -> some View {
    HStack(spacing: 5) {
      Circle().fill(palette.accent).frame(width: 6, height: 6)
      Text("QODER")
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
      Spacer()
      Text(label)
        .font(.system(size: 7, weight: .bold, design: .monospaced))
        .tracking(0.6)
        .foregroundStyle(palette.tertiaryText)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 9)
  }

  private var lastActiveText: String {
    guard let date = snapshot?.lastActiveDate else { return "尚无记录" }
    return "\(Self.dateFormatter.string(from: date)) \(Self.timeFormatter.string(from: date))"
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

  private static func compactCount(_ value: Int) -> String {
    if value < 1_000 { return "\(value)" }
    if value < 1_000_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return String(format: "%.1fM", Double(value) / 1_000_000)
  }

  // MARK: - 简约立柱配色

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
