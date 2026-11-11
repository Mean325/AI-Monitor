import SwiftUI

struct RetroPixelUsageCardView: View {
  let service: String
  let primaryTitle: String
  let primaryValue: String
  let primarySuffix: String
  let progress: CGFloat
  let remainingPercent: Int?
  let hasData: Bool
  let metricTitle: String
  let metricValue: String
  let firstFooterTitle: String
  let firstFooterValue: String
  let secondFooterTitle: String
  let secondFooterValue: String
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat

  private var tone: Tone {
    guard let remainingPercent else { return .normal }
    if remainingPercent < 15 { return .critical }
    if remainingPercent < 40 { return .warning }
    return .normal
  }

  private var safeArea: CGFloat {
    min(UsageCardLayout.maximumSafeArea, max(UsageCardLayout.minimumSafeArea, safeAreaHeight))
  }

  private var statusText: String {
    guard hasData else { return "WAIT" }
    guard remainingPercent != nil else { return "LIVE" }
    switch tone {
    case .normal: return "ONLINE"
    case .warning: return "ALERT"
    case .critical: return "CRITICAL"
    }
  }

  private var activityColor: Color {
    switch activityState {
    case .idle, .finished: return Tone.normal.accent
    case .running: return Tone.warning.accent
    case .awaitingAuthorization, .awaitingUserInput, .toolFailed, .quotaExhausted:
      return Tone.critical.accent
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Spacer(minLength: 8)
      VStack(spacing: 10) {
        VStack(spacing: 6) {
          Text(primaryTitle)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.1)
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(primaryValue)
              .font(.system(size: 38, weight: .black, design: .monospaced))
            Text(primarySuffix)
              .font(.system(size: primarySuffix == "%" ? 30 : 14,
                weight: .black, design: .monospaced))
          }
          .foregroundStyle(tone.bright)
          .shadow(color: tone.accent.opacity(0.55), radius: 4)
          .lineLimit(1)
          .minimumScaleFactor(0.45)
        }
        energyBars
        HStack(spacing: 3) {
          Text(metricTitle)
          Text(metricValue)
            .foregroundStyle(tone.bright)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(tone.accent.opacity(0.08))
        .border(tone.accent.opacity(0.4), width: 1)
      }
      Spacer(minLength: 8)
      footer
    }
    .foregroundStyle(tone.accent)
    .padding(10)
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height - safeArea)
    .padding(.top, safeArea)
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .background { dotGrid }
    .background(tone.background)
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(tone.accent.opacity(0.45), lineWidth: 1.5)
    }
    .clipped()
  }

  private var header: some View {
    HStack(spacing: 4) {
      Text("\(service)_")
        .font(.system(size: 13, weight: .black, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 0)
      Circle()
        .fill(activityColor)
        .frame(width: 4, height: 4)
        .accessibilityLabel(Text(activityState.title))
      Text(statusText)
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(tone.background)
        .border(tone.accent.opacity(0.4), width: 1)
    }
    .padding(.bottom, 7)
    .overlay(alignment: .bottom) {
      Rectangle().fill(tone.accent.opacity(0.3)).frame(height: 1)
    }
  }

  private var energyBars: some View {
    VStack(spacing: 4) {
      ForEach(0..<10, id: \.self) { index in
        let isLit = CGFloat(index) < (min(1, max(0, progress)) * 10).rounded()
        Rectangle()
          .fill(isLit ? tone.accent : tone.background)
          .overlay {
            Rectangle().strokeBorder(tone.accent.opacity(isLit ? 0.9 : 0.3), lineWidth: 1)
          }
          .shadow(color: isLit ? tone.accent.opacity(0.5) : .clear, radius: 3)
          .frame(height: 8)
      }
    }
    .padding(.horizontal, 4)
    .accessibilityLabel(Text("\(Int((min(1, max(0, progress)) * 100).rounded()))%"))
  }

  private var footer: some View {
    VStack(spacing: 5) {
      footerRow(firstFooterTitle, value: firstFooterValue)
      footerRow(secondFooterTitle, value: secondFooterValue)
    }
    .padding(.top, 8)
    .overlay(alignment: .top) {
      Rectangle().fill(tone.accent.opacity(0.3)).frame(height: 1)
    }
  }

  private func footerRow(_ title: String, value: String) -> some View {
    HStack(spacing: 3) {
      Text(title).foregroundStyle(tone.accent.opacity(0.75))
      Spacer(minLength: 0)
      Text(value).foregroundStyle(tone.bright)
    }
    .font(.system(size: 10, weight: .medium, design: .monospaced))
    .lineLimit(1)
    .minimumScaleFactor(0.6)
  }

  private var dotGrid: some View {
    Canvas { context, size in
      for y in stride(from: CGFloat(3), to: size.height, by: 6) {
        for x in stride(from: CGFloat(3), to: size.width, by: 6) {
          let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5))
          context.fill(dot, with: .color(tone.accent.opacity(0.22)))
        }
      }
    }
    .accessibilityHidden(true)
  }

  private enum Tone {
    case normal, warning, critical

    var accent: Color {
      switch self {
      case .normal: return Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
      case .warning: return Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
      case .critical: return Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255)
      }
    }

    var bright: Color {
      switch self {
      case .normal: return Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
      case .warning: return Color(red: 252 / 255, green: 211 / 255, blue: 77 / 255)
      case .critical: return Color(red: 253 / 255, green: 164 / 255, blue: 175 / 255)
      }
    }

    var background: Color {
      switch self {
      case .normal: return Color(red: 6 / 255, green: 16 / 255, blue: 9 / 255)
      case .warning: return Color(red: 17 / 255, green: 14 / 255, blue: 6 / 255)
      case .critical: return Color(red: 19 / 255, green: 7 / 255, blue: 9 / 255)
      }
    }
  }
}
