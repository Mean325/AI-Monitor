import SwiftUI

struct BrandLogoView: View {
  let mode: DisplayMode
  var size: CGFloat = 30

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    let inset = size * 0.18
    Group {
      if let name = mode.logoAssetName {
        Image(name)
          .renderingMode(.template)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .padding(inset)
          .foregroundStyle(.primary)
      } else {
        Image(systemName: mode.symbol)
          .font(.system(size: size * 0.42, weight: .semibold))
          .foregroundStyle(.primary)
          .padding(inset)
      }
    }
    .frame(width: size, height: size)
    .background(Color.primary.opacity(0.06), in: shape)
    .overlay {
      shape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}
