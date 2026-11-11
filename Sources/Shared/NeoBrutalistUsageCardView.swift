import SwiftUI

/// Fixed-color hardware layout, shared by each usage source.
struct NeoBrutalistUsageCardView: View {
  let service: String
  let headlineTitle: String
  let headlineValue: String
  let primaryTitle: String
  let primaryValue: String
  let primarySuffix: String
  let captionTitle: String
  let captionValue: String
  let progress: CGFloat
  let progressTitle: String
  let secondaryTitle: String
  let secondarySubtitle: String
  let secondaryValue: String
  let footerTitle: String
  let footerValue: String
  let activityState: CodexActivityState
  let safeAreaHeight: CGFloat

  private let yellow = Color(red: 255 / 255, green: 222 / 255, blue: 89 / 255)
  private let red = Color(red: 255 / 255, green: 87 / 255, blue: 87 / 255)
  private let green = Color(red: 0, green: 230 / 255, blue: 118 / 255)

  private var safeArea: CGFloat {
    min(UsageCardLayout.maximumSafeArea, max(UsageCardLayout.minimumSafeArea, safeAreaHeight))
  }

  private var activityColor: Color {
    switch activityState {
    case .idle, .finished: return green
    case .running: return yellow
    case .awaitingAuthorization, .awaitingUserInput, .toolFailed, .quotaExhausted: return red
    }
  }

  private var activityText: String {
    switch activityState {
    case .idle: return "空闲"
    case .finished: return "已完成"
    case .running: return "执行中"
    case .awaitingAuthorization: return "待授权"
    case .awaitingUserInput: return "待回复"
    case .toolFailed: return "失败"
    case .quotaExhausted: return "额度不足"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headline
      Spacer(minLength: 8)
      primaryPanel
      Spacer(minLength: 8)
      progressPanel
      Spacer(minLength: 8)
      hazardStripe
      Spacer(minLength: 8)
      secondaryPanel
      Spacer(minLength: 8)
      footer
    }
    .font(.system(size: 8, weight: .black))
    .foregroundStyle(Color.black)
    .padding(.horizontal, 10)
    .padding(.top, safeArea + 8)
    .padding(.bottom, 10)
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .background(yellow)
    .clipped()
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 3) {
        Text(headlineTitle)
          .font(.system(size: 7, weight: .black, design: .monospaced))
          .foregroundStyle(yellow)
        Spacer(minLength: 0)
        Text(activityText)
          .font(.system(size: 7, weight: .black))
          .foregroundStyle(Color.black)
          .padding(.horizontal, 3)
          .padding(.vertical, 2)
          .background(activityColor)
          .accessibilityLabel(Text(activityState.title))
      }
      Text(headlineValue)
        .font(.system(size: 10, weight: .heavy, design: .monospaced))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
    .padding(7)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 4))
  }

  private var primaryPanel: some View {
    VStack(spacing: 4) {
      HStack(spacing: 3) {
        Text(primaryTitle)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(Color.white)
          .border(Color.black, width: 1)
        Spacer(minLength: 0)
        Text(service)
          .font(.system(size: 6, weight: .black, design: .monospaced))
          .foregroundStyle(Color.white)
          .padding(3)
          .background(red)
          .border(Color.black, width: 1)
      }
      VStack(spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(primaryValue)
            .font(.system(size: 32, weight: .black, design: .rounded))
            .minimumScaleFactor(0.5)
          Spacer(minLength: 0)
          Text(primarySuffix)
            .font(.system(size: 14, weight: .black, design: .rounded))
        }
        Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1)
        HStack(spacing: 3) {
          Text(captionTitle)
          Spacer(minLength: 0)
          Text(captionValue)
            .font(.system(size: 7, weight: .black, design: .monospaced))
        }
        .font(.system(size: 7, weight: .black))
      }
      .padding(7)
      .frame(maxWidth: .infinity)
      .modifier(HardEdgePanel(fill: .white, borderWidth: 2))
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }

  private var progressPanel: some View {
    VStack(spacing: 4) {
      HStack(spacing: 2) {
        Text(progressTitle)
        Spacer(minLength: 0)
        Text("\(Int((min(1, max(0, progress)) * 100).rounded()))%")
          .font(.system(size: 7, weight: .black, design: .monospaced))
      }
      .font(.system(size: 7, weight: .black))
      HStack(spacing: 2) {
        ForEach(0..<8, id: \.self) { index in
          Rectangle()
            .fill(segmentColor(at: index))
            .overlay { Rectangle().strokeBorder(Color.black, lineWidth: 1) }
        }
      }
      .padding(3)
      .frame(height: 24)
      .modifier(HardEdgePanel(fill: .white, borderWidth: 1))
    }
  }

  private func segmentColor(at index: Int) -> Color {
    let filledSegments = min(1, max(0, progress)) * 8
    if CGFloat(index + 1) <= filledSegments { return green }
    if CGFloat(index) < filledSegments { return yellow }
    return Color(white: 0.88)
  }

  private var hazardStripe: some View {
    Canvas { context, size in
      for x in stride(from: -size.height, to: size.width + size.height, by: 12) {
        var stripe = Path()
        stripe.move(to: CGPoint(x: x, y: 0))
        stripe.addLine(to: CGPoint(x: x + 6, y: 0))
        stripe.addLine(to: CGPoint(x: x + 6 + size.height, y: size.height))
        stripe.addLine(to: CGPoint(x: x + size.height, y: size.height))
        stripe.closeSubpath()
        context.fill(stripe, with: .color(.black))
      }
    }
    .frame(height: 8)
    .background(yellow)
    .border(Color.black, width: 1)
    .accessibilityHidden(true)
  }

  private var secondaryPanel: some View {
    HStack(spacing: 5) {
      VStack(alignment: .leading, spacing: 4) {
        Text(secondaryTitle)
        Text(secondarySubtitle)
          .font(.system(size: 7, weight: .black, design: .monospaced))
      }
      .foregroundStyle(Color.white)
      Spacer(minLength: 0)
      Text(secondaryValue)
        .font(.system(size: 14, weight: .black, design: .monospaced))
        .foregroundStyle(yellow)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 3))
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: 1) }
    }
    .lineLimit(1)
    .minimumScaleFactor(0.55)
    .padding(7)
    .frame(maxWidth: .infinity, minHeight: 52)
    .modifier(HardEdgePanel(fill: red, borderWidth: 1))
  }

  private var footer: some View {
    HStack(spacing: 3) {
      Text(footerTitle)
      Spacer(minLength: 0)
      Text(footerValue)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .padding(3)
        .background(yellow)
        .border(Color.black, width: 1)
    }
    .font(.system(size: 7, weight: .black))
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .padding(5)
    .modifier(HardEdgePanel(fill: .white, borderWidth: 1))
  }
}

private struct HardEdgePanel: ViewModifier {
  let fill: Color
  let borderWidth: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 3)
    content
      .background(fill, in: shape)
      .overlay { shape.strokeBorder(Color.black, lineWidth: borderWidth) }
      .background { shape.fill(Color.black).offset(x: 2, y: 2) }
  }
}
