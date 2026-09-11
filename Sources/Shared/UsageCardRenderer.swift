import AppKit
import SwiftUI

enum UsageCardRendererError: LocalizedError {
  case renderFailed
  case encodingFailed
  case invalidDimensions
  case fileTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .renderFailed:
      return "无法生成屏幕图片。"
    case .encodingFailed:
      return "无法编码 JPEG 图片。"
    case .invalidDimensions:
      return "屏幕图片尺寸不是 142×428。"
    case .fileTooLarge(let bytes):
      return "屏幕图片为 \(bytes) 字节，超过 512KB 限制。"
    }
  }
}

struct RenderedUsageCard {
  let data: Data
  let image: NSImage
  let pixelWidth: Int
  let pixelHeight: Int
}

private let previewScale: CGFloat = 2

@MainActor
enum CustomImageRenderer {
  static func render(
    image: NSImage,
    safeAreaHeight: CGFloat,
    jpegQuality: Double
  ) throws -> RenderedUsageCard {
    let safeArea = max(
      UsageCardLayout.minimumSafeArea,
      min(UsageCardLayout.maximumSafeArea, safeAreaHeight)
    )
    let contentHeight = UsageCardLayout.height - safeArea

    let view = VStack(spacing: 0) {
      Color.black
        .frame(width: UsageCardLayout.width, height: safeArea)

      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: UsageCardLayout.width, height: contentHeight)
        .clipped()
    }
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .background(Color.black)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }

    let previewRenderer = ImageRenderer(content: view)
    previewRenderer.proposedSize = renderer.proposedSize
    previewRenderer.scale = previewScale
    previewRenderer.isOpaque = true

    guard let previewCGImage = previewRenderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(
      cgImage: cgImage,
      previewCGImage: previewCGImage,
      jpegQuality: jpegQuality
    )
  }
}

@MainActor
enum UsageCardRenderer {
  static func render(
    snapshot: UsageSnapshot?,
    activityState: CodexActivityState = .idle,
    safeAreaHeight: CGFloat,
    jpegQuality: Double,
    colorScheme: UsageCardColorScheme = .deepSpace,
    design: UsageCardDesign = .minimalColumn
  ) throws -> RenderedUsageCard {
    let view = UsageCardView(
      snapshot: snapshot,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight,
      colorScheme: colorScheme,
      design: design
    )
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }

    let previewRenderer = ImageRenderer(content: view)
    previewRenderer.proposedSize = renderer.proposedSize
    previewRenderer.scale = previewScale
    previewRenderer.isOpaque = true

    guard let previewCGImage = previewRenderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(
      cgImage: cgImage,
      previewCGImage: previewCGImage,
      jpegQuality: jpegQuality
    )
  }

  static func render(
    claudeSnapshot: ClaudeCodeUsageSnapshot?,
    activityState: CodexActivityState = .idle,
    safeAreaHeight: CGFloat,
    jpegQuality: Double,
    colorScheme: UsageCardColorScheme = .deepSpace,
    design: UsageCardDesign = .minimalColumn
  ) throws -> RenderedUsageCard {
    let view = ClaudeCodeCardView(
      snapshot: claudeSnapshot,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight,
      colorScheme: colorScheme,
      design: design
    )
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }

    let previewRenderer = ImageRenderer(content: view)
    previewRenderer.proposedSize = renderer.proposedSize
    previewRenderer.scale = previewScale
    previewRenderer.isOpaque = true

    guard let previewCGImage = previewRenderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(
      cgImage: cgImage,
      previewCGImage: previewCGImage,
      jpegQuality: jpegQuality
    )
  }

  static func render(
    qoderSnapshot: QoderUsageSnapshot?,
    creditSnapshot: QoderCreditSnapshot? = nil,
    activityState: CodexActivityState = .idle,
    safeAreaHeight: CGFloat,
    jpegQuality: Double,
    colorScheme: UsageCardColorScheme = .deepSpace,
    design: UsageCardDesign = .minimalColumn
  ) throws -> RenderedUsageCard {
    let view = QoderCardView(
      snapshot: qoderSnapshot,
      creditSnapshot: creditSnapshot,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight,
      colorScheme: colorScheme,
      design: design
    )
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }

    let previewRenderer = ImageRenderer(content: view)
    previewRenderer.proposedSize = renderer.proposedSize
    previewRenderer.scale = previewScale
    previewRenderer.isOpaque = true

    guard let previewCGImage = previewRenderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(
      cgImage: cgImage,
      previewCGImage: previewCGImage,
      jpegQuality: jpegQuality
    )
  }

  static func render(
    grokSnapshot: GrokUsageSnapshot?,
    activityState: CodexActivityState = .idle,
    safeAreaHeight: CGFloat,
    jpegQuality: Double,
    colorScheme: UsageCardColorScheme = .deepSpace,
    design: UsageCardDesign = .minimalColumn
  ) throws -> RenderedUsageCard {
    let view = GrokCardView(
      snapshot: grokSnapshot,
      activityState: activityState,
      safeAreaHeight: safeAreaHeight,
      colorScheme: colorScheme,
      design: design
    )
      .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(
      width: UsageCardLayout.width, height: UsageCardLayout.height)
    renderer.scale = 1
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }

    let previewRenderer = ImageRenderer(content: view)
    previewRenderer.proposedSize = renderer.proposedSize
    previewRenderer.scale = previewScale
    previewRenderer.isOpaque = true

    guard let previewCGImage = previewRenderer.cgImage else {
      throw UsageCardRendererError.renderFailed
    }
    return try makeRenderedImage(
      cgImage: cgImage,
      previewCGImage: previewCGImage,
      jpegQuality: jpegQuality
    )
  }
}

private func makeRenderedImage(
  cgImage: CGImage,
  previewCGImage: CGImage,
  jpegQuality: Double
) throws -> RenderedUsageCard {
  guard cgImage.width == Int(UsageCardLayout.width), cgImage.height == Int(UsageCardLayout.height)
  else {
    throw UsageCardRendererError.invalidDimensions
  }
  guard
    previewCGImage.width == cgImage.width * Int(previewScale),
    previewCGImage.height == cgImage.height * Int(previewScale)
  else {
    throw UsageCardRendererError.renderFailed
  }

  let representation = NSBitmapImageRep(cgImage: cgImage)
  guard
    let data = representation.representation(
      using: .jpeg,
      properties: [.compressionFactor: max(0.5, min(1, jpegQuality))]
    )
  else {
    throw UsageCardRendererError.encodingFailed
  }
  guard data.count <= 512 * 1_024 else {
    throw UsageCardRendererError.fileTooLarge(data.count)
  }

  return RenderedUsageCard(
    data: data,
    image: NSImage(
      cgImage: previewCGImage,
      size: NSSize(width: cgImage.width, height: cgImage.height)
    ),
    pixelWidth: cgImage.width,
    pixelHeight: cgImage.height
  )
}
