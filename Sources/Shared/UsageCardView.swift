import SwiftUI

enum UsageCardLayout {
  static let width: CGFloat = 142
  static let height: CGFloat = 428
  static let defaultSafeArea: CGFloat = 56
  static let minimumSafeArea: CGFloat = 44
  static let maximumSafeArea: CGFloat = 80
}

struct NothingUsageCardView: View {
  let palette: UsageCardPalette
  let service: String
  let primaryTitle: String
  let primaryValue: String
  let primarySuffix: String
  let primaryCaption: String
  let progress: CGFloat
  let firstMetricTitle: String
  let firstMetricValue: String
  let secondMetricTitle: String?
  let secondMetricValue: String?
  let noticeTitle: String?
  let noticeValue: String?
  let footerTitle: String
  let footerValue: String
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat

  private var background: Color { palette.background }
  private var surface: Color { palette.cardBackground }
  private var raisedSurface: Color { palette.insetBackground }
  private var onSurface: Color { palette.primaryText }
  private var secondary: Color { palette.secondaryText }
  private var nothingAccent: Color { palette.accent }

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
    ZStack(alignment: .topLeading) {
      background

      VStack(alignment: .leading, spacing: layoutSpacing) {
        header
        primaryPanel

        HStack(spacing: 8) {
          if let secondMetricTitle, let secondMetricValue {
            metricPanel(title: firstMetricTitle, value: firstMetricValue, width: 49)
            metricPanel(title: secondMetricTitle, value: secondMetricValue, width: 61)
          } else {
            metricPanel(title: firstMetricTitle, value: firstMetricValue, width: 118)
          }
        }
        .frame(height: metricsHeight)

        if let noticeTitle, let noticeValue {
          noticePanel(title: noticeTitle, value: noticeValue)
        }

        footer
      }
      .frame(width: 118, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.top, safeAreaHeight + 10)
      .padding(.bottom, 8)
    }
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .clipped()
  }

  private var header: some View {
    HStack(spacing: 8) {
      DotMatrixText(text: service, dotSize: headerDotSize, color: onSurface)
      Spacer(minLength: 0)
      Circle()
        .fill(activityColor)
        .frame(width: 11, height: 11)
        .shadow(color: activityColor.opacity(0.65), radius: 4)
        .accessibilityLabel(Text(activityState.title))
    }
    .frame(width: 118, height: headerHeight)
  }

  @ViewBuilder
  private var primaryPanel: some View {
    if hasNotice {
      VStack(alignment: .leading, spacing: 0) {
        primaryTitleView
        primaryValueView
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
      .padding(.horizontal, 10)
      .padding(.top, 7)
      .padding(.bottom, 7)
      .frame(width: 118, height: primaryPanelHeight)
      .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    } else {
      VStack(alignment: .leading, spacing: 5) {
        primaryTitleView
        primaryValueView

        if !primaryCaption.isEmpty {
          Text(primaryCaption)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(secondary)
            .lineLimit(1)
        }

        segmentedProgress
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(width: 118, height: primaryPanelHeight, alignment: .topLeading)
      .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }

  private var primaryTitleView: some View {
    Text(primaryTitle.uppercased())
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .tracking(0.8)
      .foregroundStyle(secondary)
      .lineLimit(1)
  }

  private var primaryValueView: some View {
    HStack(alignment: .bottom, spacing: 5) {
      DotMatrixText(text: primaryValue, dotSize: primaryDotSize, color: onSurface)

      if primarySuffix == "%" {
        DotMatrixText(text: primarySuffix, dotSize: 2.2, color: nothingAccent)
          .padding(.bottom, 1)
      } else {
        Text(primarySuffix)
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundStyle(nothingAccent)
          .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private func metricPanel(title: String, value: String, width: CGFloat) -> some View {
    if width >= 100 {
      VStack(alignment: .leading, spacing: 0) {
        metricTitle(title)
        NothingMetricValue(value: value, color: onSurface, secondary: secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
      .padding(.horizontal, 6)
      .padding(.top, 7)
      .padding(.bottom, 7)
      .frame(width: width)
      .frame(maxHeight: .infinity)
      .background(surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      VStack(alignment: .leading, spacing: 5) {
        metricTitle(title)
        NothingMetricValue(value: value, color: onSurface, secondary: secondary)
      }
      .padding(.horizontal, 6)
      .padding(.top, 7)
      .frame(width: width, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
      .background(surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  private func metricTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 8, weight: .medium, design: .monospaced))
      .foregroundStyle(secondary)
      .lineLimit(1)
  }

  private func noticePanel(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      HStack {
        NothingMetricValue(value: value, color: onSurface, secondary: secondary)
        Spacer(minLength: 0)
      }
      segmentedProgress
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(width: 118, height: noticeHeight)
    .background(surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var segmentedProgress: some View {
    GeometryReader { proxy in
      HStack(spacing: 3) {
        ForEach(0..<10, id: \.self) { index in
          RoundedRectangle(cornerRadius: 1.5)
            .fill(CGFloat(index) / 10 < min(1, max(0, progress)) ? nothingAccent : raisedSurface)
            .frame(width: max(0, (proxy.size.width - 27) / 10))
        }
      }
    }
    .frame(height: 6)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Rectangle().fill(nothingAccent).frame(width: 3, height: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(footerTitle)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(secondary)
        DotMatrixText(text: compactFooterValue, dotSize: 1.15, color: onSurface)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(width: 118, height: footerHeight)
    .background(raisedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
  }

  private var compactFooterValue: String {
    footerValue
      .replacingOccurrences(of: "月", with: "/")
      .replacingOccurrences(of: "日", with: "")
      .replacingOccurrences(of: "  ", with: " ")
  }

  private var primaryDotSize: CGFloat {
    if service == "CODEX" && primaryValue.count <= 2 { return 5 }
    if primaryValue.count <= 2 { return 4.2 }
    if primaryValue.count <= 4 { return 3 }
    return 1.9
  }
  private var headerDotSize: CGFloat { service == "CODEX" ? 2 : 1.75 }
  private var headerHeight: CGFloat { service == "CODEX" ? 22 : 18 }

  private var hasNotice: Bool { noticeTitle != nil && noticeValue != nil }
  private var layoutSpacing: CGFloat {
    if hasNotice { return 10 }
    return safeAreaHeight >= 70 ? 8 : 14
  }
  private var primaryPanelHeight: CGFloat {
    if hasNotice { return 108 }
    return safeAreaHeight >= 70 ? 112 : 136
  }
  private var metricsHeight: CGFloat {
    if hasNotice { return 66 }
    return safeAreaHeight >= 70 ? 64 : 76
  }
  private var noticeHeight: CGFloat { 60 }
  private var footerHeight: CGFloat { hasNotice ? 46 : (safeAreaHeight >= 70 ? 48 : 56) }
}

private struct NothingMetricValue: View {
  let value: String
  let color: Color
  let secondary: Color

  private var numericPrefix: String {
    String(value.prefix { "0123456789.-/%:kKmM ".contains($0) })
      .trimmingCharacters(in: .whitespaces)
  }

  private var suffix: String {
    String(value.dropFirst(numericPrefix.count)).trimmingCharacters(in: .whitespaces)
  }

  var body: some View {
    if numericPrefix.isEmpty {
      DotMatrixText(
        text: value,
        dotSize: value.count > 6 ? 0.9 : (value.count > 4 ? 1.15 : 1.5),
        color: color
      )
    } else {
      HStack(alignment: .bottom, spacing: 3) {
        DotMatrixText(text: numericPrefix, dotSize: 2, color: color)
        if !suffix.isEmpty {
          Text(suffix)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(secondary)
        }
      }
    }
  }
}

private struct DotMatrixText: View {
  let text: String
  let dotSize: CGFloat
  let color: Color

  private var glyphSpacing: CGFloat { max(1, dotSize * 0.8) }
  private var cellSpacing: CGFloat { max(0.55, dotSize * 0.42) }

  var body: some View {
    HStack(alignment: .top, spacing: glyphSpacing) {
      ForEach(Array(text.uppercased().enumerated()), id: \.offset) { _, character in
        glyph(for: character)
      }
    }
    .fixedSize(horizontal: true, vertical: true)
    .accessibilityLabel(Text(text))
  }

  private func glyph(for character: Character) -> some View {
    let rows = Self.patterns[character] ?? Self.patterns["?"]!
    return VStack(spacing: cellSpacing) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: cellSpacing) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
            Circle()
              .fill(cell == "1" ? color : Color.clear)
              .frame(width: dotSize, height: dotSize)
          }
        }
      }
    }
  }

  private static let patterns: [Character: [String]] = [
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
    "%": ["11001", "11010", "00100", "01000", "10110", "00110", "00000"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
  ]
}

enum UsageCardColorScheme: String, CaseIterable, Identifiable {
  case deepSpace
  case auroraBlue
  case fusionMagenta
  case peachGlow
  case cloudDancer
  case signalYellow
  case rainbow

  var id: String { rawValue }

  var title: String {
    switch self {
    case .deepSpace: return "深空青"
    case .auroraBlue: return "极光蓝"
    case .fusionMagenta: return "熔芯红"
    case .peachGlow: return "柔桃光"
    case .cloudDancer: return "云迹白"
    case .signalYellow: return "信号黄"
    case .rainbow: return "彩虹"
    }
  }

  var subtitle: String {
    switch self {
    case .deepSpace: return "沉稳"
    case .auroraBlue: return "Very Peri"
    case .fusionMagenta: return "Viva Magenta"
    case .peachGlow: return "Peach Fuzz"
    case .cloudDancer: return "Cloud Dancer"
    case .signalYellow: return "灰黄"
    case .rainbow: return "余量"
    }
  }

  var symbol: String {
    switch self {
    case .deepSpace: return "sparkles"
    case .auroraBlue: return "wave.3.right"
    case .fusionMagenta: return "bolt.fill"
    case .peachGlow: return "sun.horizon.fill"
    case .cloudDancer: return "cloud.fill"
    case .signalYellow: return "scope"
    case .rainbow: return "rainbow"
    }
  }

  var previewSwatches: [Color] {
    switch self {
    case .rainbow:
      return [
        Self.rainbowAccent(remainingPercent: 10),
        Self.rainbowAccent(remainingPercent: 30),
        Self.rainbowAccent(remainingPercent: 70),
        Self.rainbowAccent(remainingPercent: 90),
      ]
    default:
      return [palette.accent, palette.primaryText]
    }
  }

  var palette: UsageCardPalette {
    palette(remainingPercent: nil)
  }

  func palette(remainingPercent: Int?) -> UsageCardPalette {
    let base = staticPalette
    guard self == .rainbow else { return base }
    return base.replacingAccent(Self.rainbowAccent(remainingPercent: remainingPercent))
  }

  /// 0–20 `#E8526F`, 20–40 `#F5DF4D`, 40–80 `#55E6B8` (40–60 unspecified, shares 60–80), 80–100 `#00B176`.
  static func rainbowAccent(remainingPercent: Int?) -> Color {
    guard let remainingPercent else {
      return rgb(0, 177, 118)
    }
    switch remainingPercent {
    case ...20:
      return rgb(232, 82, 111)
    case ...40:
      return rgb(245, 223, 77)
    case ...80:
      return rgb(85, 230, 184)
    default:
      return rgb(0, 177, 118)
    }
  }

  private var staticPalette: UsageCardPalette {
    switch self {
    case .deepSpace:
      return UsageCardPalette(
        background: rgb(8, 11, 18),
        cardBackground: rgb(17, 24, 39),
        insetBackground: rgb(11, 18, 32),
        border: rgb(38, 52, 74),
        accent: rgb(85, 230, 184),
        primaryText: rgb(248, 250, 252),
        secondaryText: rgb(148, 163, 184),
        tertiaryText: rgb(100, 116, 139)
      )
    case .auroraBlue:
      // A restrained tonal scale built around Pantone Very Peri.
      return UsageCardPalette(
        background: rgb(14, 15, 35),
        cardBackground: rgb(31, 33, 65),
        insetBackground: rgb(22, 23, 48),
        border: rgb(67, 71, 112),
        accent: rgb(123, 130, 222),
        primaryText: rgb(218, 221, 250),
        secondaryText: rgb(166, 171, 211),
        tertiaryText: rgb(112, 117, 158)
      )
    case .fusionMagenta:
      // Viva Magenta carried through wine-dark surfaces and dusty rose text.
      return UsageCardPalette(
        background: rgb(23, 10, 17),
        cardBackground: rgb(52, 21, 34),
        insetBackground: rgb(37, 14, 24),
        border: rgb(104, 46, 68),
        accent: rgb(232, 82, 111),
        primaryText: rgb(240, 211, 219),
        secondaryText: rgb(207, 145, 162),
        tertiaryText: rgb(148, 98, 112)
      )
    case .peachGlow:
      // Peach Fuzz softened with cocoa neutrals instead of a competing cool hue.
      return UsageCardPalette(
        background: rgb(27, 18, 15),
        cardBackground: rgb(55, 37, 31),
        insetBackground: rgb(40, 26, 22),
        border: rgb(108, 74, 61),
        accent: rgb(255, 190, 152),
        primaryText: rgb(235, 218, 207),
        secondaryText: rgb(202, 159, 140),
        tertiaryText: rgb(143, 108, 95)
      )
    case .cloudDancer:
      // Cloud Dancer with breezy blue and aqueous blue-green from Atmospheric.
      return UsageCardPalette(
        background: rgb(16, 20, 24),
        cardBackground: rgb(37, 43, 46),
        insetBackground: rgb(26, 32, 35),
        border: rgb(89, 97, 102),
        accent: rgb(240, 238, 233),
        primaryText: rgb(168, 216, 234),
        secondaryText: rgb(143, 209, 195),
        tertiaryText: rgb(156, 166, 167)
      )
    case .signalYellow:
      // Ultimate Gray and Illuminating, adapted for a dark industrial display.
      return UsageCardPalette(
        background: rgb(17, 18, 19),
        cardBackground: rgb(41, 43, 45),
        insetBackground: rgb(29, 31, 32),
        border: rgb(94, 96, 98),
        accent: rgb(245, 223, 77),
        primaryText: rgb(190, 192, 194),
        secondaryText: rgb(245, 235, 174),
        tertiaryText: rgb(147, 149, 151)
      )
    case .rainbow:
      return UsageCardPalette(
        background: rgb(8, 14, 12),
        cardBackground: rgb(18, 28, 24),
        insetBackground: rgb(13, 21, 18),
        border: rgb(42, 64, 54),
        accent: Self.rainbowAccent(remainingPercent: nil),
        primaryText: rgb(200, 210, 206),
        secondaryText: rgb(132, 158, 148),
        tertiaryText: rgb(92, 114, 106)
      )
    }
  }

  private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Self.rgb(red, green, blue)
  }

  private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Color(red: red / 255, green: green / 255, blue: blue / 255)
  }
}

enum UsageCardDesign: String, CaseIterable, Identifiable {
  case classic
  case orbitalRings
  case liquidGlass
  case commandDeck
  case minimalColumn
  case nothingMatrix

  var id: String { rawValue }

  var title: String {
    switch self {
    case .classic: return "经典卡片"
    case .orbitalRings: return "轨道圆环"
    case .liquidGlass: return "液态玻璃"
    case .commandDeck: return "指挥舱"
    case .minimalColumn: return "简约立柱"
    case .nothingMatrix: return "Nothing 矩阵"
    }
  }

  var subtitle: String {
    switch self {
    case .classic: return "当前布局"
    case .orbitalRings: return "动态圆环"
    case .liquidGlass: return "柔光层叠"
    case .commandDeck: return "数据仪表"
    case .minimalColumn: return "纵向进度"
    case .nothingMatrix: return "黑白点阵"
    }
  }

  var symbol: String {
    switch self {
    case .classic: return "rectangle.inset.filled"
    case .orbitalRings: return "circle.circle"
    case .liquidGlass: return "drop.fill"
    case .commandDeck: return "scope"
    case .minimalColumn: return "rectangle.split.1x2.fill"
    case .nothingMatrix: return "circle.grid.3x3.fill"
    }
  }

  var usesFullCanvas: Bool {
    self == .minimalColumn || self == .nothingMatrix
  }
}

struct UsageCardPalette {
  let background: Color
  let cardBackground: Color
  let insetBackground: Color
  let border: Color
  let accent: Color
  let primaryText: Color
  let secondaryText: Color
  let tertiaryText: Color

  func replacingAccent(_ accent: Color) -> UsageCardPalette {
    UsageCardPalette(
      background: background,
      cardBackground: cardBackground,
      insetBackground: insetBackground,
      border: border,
      accent: accent,
      primaryText: primaryText,
      secondaryText: secondaryText,
      tertiaryText: tertiaryText
    )
  }
}

struct UsageCardView: View {
  let snapshot: UsageSnapshot?
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat
  let colorScheme: UsageCardColorScheme
  let design: UsageCardDesign

  private var palette: UsageCardPalette {
    colorScheme.palette(remainingPercent: snapshot?.remainingPercent)
  }
  private var remainingProgress: CGFloat {
    CGFloat(max(0, min(100, snapshot?.remainingPercent ?? 0))) / 100
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
  private var activityIndicatorColor: Color {
    switch activityState {
    case .idle:
      return Color(red: 51 / 255, green: 199 / 255, blue: 110 / 255)
    case .finished:
      return Color(red: 51 / 255, green: 199 / 255, blue: 110 / 255)
    case .running:
      return Color(red: 255 / 255, green: 199 / 255, blue: 31 / 255)
    case .awaitingAuthorization:
      return Color(red: 242 / 255, green: 56 / 255, blue: 64 / 255)
    case .toolFailed:
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
      service: "CODEX",
      primaryTitle: snapshot?.windowTitle ?? "周期剩余",
      primaryValue: snapshot.map { "\($0.remainingPercent)" } ?? "--",
      primarySuffix: "%",
      primaryCaption: snapshot == nil ? "等待用量同步" : "",
      progress: remainingProgress,
      firstMetricTitle: "可用重置",
      firstMetricValue: snapshot.map { "\($0.availableResetCount) 次" } ?? "--",
      secondMetricTitle: nil,
      secondMetricValue: nil,
      noticeTitle: "周期到期",
      noticeValue: periodExpiryText,
      footerTitle: "下次重置",
      footerValue: "\(resetDateText)  \(resetTimeText)",
      activityState: activityState,
      safeAreaHeight: safeAreaHeight
    )
  }

  private var periodExpiryText: String {
    guard let description = snapshot?.windowDescription else { return "--" }
    return description.replacingOccurrences(of: "周期", with: "到期")
  }

  private var classicLayout: some View {
    VStack(spacing: 0) {
      classicHeader
        .frame(height: 38)

      Rectangle()
        .fill(palette.border)
        .frame(height: 1)
        .padding(.horizontal, 9)

      classicUsageSection
        .frame(height: 112)

      classicResetCard
        .frame(width: 106, height: 70)
        .padding(.top, 12)

      Spacer(minLength: 16)

      classicAutoResetSection
        .padding(.bottom, 16)
    }
  }

  private var classicHeader: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(palette.accent)
        .frame(width: 8, height: 8)

      Text("CODEX")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(palette.primaryText)

      Spacer(minLength: 2)

      Text(snapshot == nil ? "等待" : "实时")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(snapshot == nil ? palette.tertiaryText : palette.accent)
    }
    .padding(.horizontal, 9)
  }

  private var classicUsageSection: some View {
    VStack(spacing: 0) {
      Text(snapshot?.windowTitle ?? "等待同步")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(palette.secondaryText)
        .padding(.top, 11)

      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
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

  private var classicResetCard: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(palette.insetBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(palette.border, lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 4) {
        Text("可用重置")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.secondaryText)

        HStack(alignment: .firstTextBaseline) {
          Text(snapshot.map { "\($0.availableResetCount)" } ?? "--")
            .font(.system(size: 31, weight: .bold, design: .rounded))
            .foregroundStyle(palette.primaryText)

          Spacer()

          Text("次")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(palette.accent)
        }
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 9)
    }
  }

  private var classicAutoResetSection: some View {
    VStack(spacing: 5) {
      Text("自动重置")
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
      compactHeader(label: "ORBIT")
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
          .overlay {
            Circle().stroke(palette.primaryText.opacity(0.08), lineWidth: 1)
          }

        VStack(spacing: -1) {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
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
        orbitalMetricPanel(title: "可用重置") {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(snapshot.map { "\($0.availableResetCount)" } ?? "--")
              .font(.system(size: 27, weight: .bold, design: .rounded))
              .foregroundStyle(palette.primaryText)
            Text("次")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(palette.accent)
          }
        }

        orbitalMetricPanel(title: "自动重置") {
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

      HStack(spacing: 8) {
        ZStack {
          Circle()
            .stroke(palette.accent.opacity(0.28), lineWidth: 1)
          Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Circle()
            .fill(palette.accent)
            .frame(width: 4, height: 4)
        }
        .frame(width: 20, height: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text("数据状态")
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(palette.tertiaryText)
          Text(snapshot == nil ? "等待同步" : "实时更新")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.primaryText)
        }

        Spacer(minLength: 0)

        HStack(alignment: .bottom, spacing: 2) {
          Capsule().frame(width: 3, height: 5)
          Capsule().frame(width: 3, height: 9)
          Capsule().frame(width: 3, height: 13)
          Capsule().frame(width: 3, height: 8)
        }
        .foregroundStyle(palette.accent.opacity(snapshot == nil ? 0.28 : 0.82))
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
        Text(snapshot == nil ? "等待数据" : "用量实时数据")
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
      compactHeader(label: "LIQUID")
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
            Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
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

          Text(snapshot?.windowDescription ?? "尚无数据")
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
            Text("可用重置")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(palette.secondaryText)
            Text("额度恢复机会")
              .font(.system(size: 7, weight: .medium))
              .foregroundStyle(palette.tertiaryText)
          }
          Spacer()
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(snapshot.map { "\($0.availableResetCount)" } ?? "--")
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
          Text("自动重置")
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
      compactHeader(label: "DASH")
        .frame(height: 30)

      VStack(alignment: .leading, spacing: 5) {
        Text(snapshot?.windowTitle.uppercased() ?? "等待同步")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .tracking(1)
          .foregroundStyle(palette.secondaryText)

        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
            .font(.system(size: 45, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .layoutPriority(1)
          Text("% 剩余")
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
        commandMetric(
          title: "可用重置",
          value: snapshot.map { "\($0.availableResetCount)" } ?? "--",
          suffix: "次"
        )
        commandMetric(title: "重置日期", value: resetDateText, suffix: "")
      }
      .frame(height: 68)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("自动重置")
            .font(.system(size: 9, weight: .semibold))
          Spacer()
          Text(snapshot == nil ? "等待" : "已计划")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(palette.accent)
        }
        .foregroundStyle(palette.tertiaryText)

        Text(resetTimeText)
          .font(.system(size: 31, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.accent)
          .frame(maxWidth: .infinity, alignment: .leading)
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
          Text("CODEX")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1)
            .foregroundStyle(chronosOnSurface)

          HStack(spacing: 5) {
            ZStack {
              Circle()
                .fill(activityIndicatorColor.opacity(0.18))
                .frame(width: 14, height: 14)

              Circle()
                .fill(activityIndicatorColor)
                .frame(width: 8, height: 8)
            }
            .shadow(color: activityIndicatorColor.opacity(0.75), radius: 4)

            Text(activityState.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(chronosOnSurfaceVariant)
          }
        }

        Spacer(minLength: 10)

        VStack(alignment: .leading, spacing: 3) {
          Text("剩余用量")
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(chronosOnSurfaceVariant)

          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
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
            Text("可用重置")
              .font(.system(size: 10, weight: .medium))
              .tracking(0.4)
              .foregroundStyle(chronosOnSurfaceVariant)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text(snapshot.map { "\($0.availableResetCount)" } ?? "--")
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
            Text("重置日期")
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
      Text("CODEX")
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

  private var resetDateText: String {
    guard let date = snapshot?.resetDate else { return "--月--日" }
    return Self.dateFormatter.string(from: date)
  }

  private var resetISODateText: String {
    guard let date = snapshot?.resetDate else { return "----/--/--" }
    return Self.isoDateFormatter.string(from: date)
  }

  private var resetTimeText: String {
    guard let date = snapshot?.resetDate else { return "--:--" }
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

  private var chronosSecondary: Color {
    Color(red: 57 / 255, green: 1, blue: 20 / 255)
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
