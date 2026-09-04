import AppKit
import SwiftUI
import XCTest

@testable import CodexLinxDisplay

final class UsageCardRendererTests: XCTestCase {
  @MainActor
  func testPopupFiveHourDataDoesNotChangeKeyboardImage() throws {
    var snapshot = UsageSnapshot.sample
    let before = try UsageCardRenderer.render(snapshot: snapshot,
      safeAreaHeight: UsageCardLayout.defaultSafeArea, jpegQuality: 0.9)
    snapshot.fiveHourRemainingPercent = 42
    snapshot.fiveHourResetDate = Date(timeIntervalSince1970: 1800000000)
    let after = try UsageCardRenderer.render(snapshot: snapshot,
      safeAreaHeight: UsageCardLayout.defaultSafeArea, jpegQuality: 0.9)
    XCTAssertEqual(before.data, after.data)
  }

  @MainActor
  func testPopulatedCardHasDeviceDimensionsAndSizeLimit() throws {
    let rendered = try UsageCardRenderer.render(
      snapshot: .sample,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
    XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)
    XCTAssertEqual(rendered.image.size, NSSize(width: 142, height: 428))
    XCTAssertEqual(rendered.image.representations.first?.pixelsWide, 284)
    XCTAssertEqual(rendered.image.representations.first?.pixelsHigh, 856)
  }

  @MainActor
  func testEmptyCardAlsoRenders() throws {
    let rendered = try UsageCardRenderer.render(
      snapshot: nil,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
  }

  @MainActor
  func testEveryColorSchemeProducesDistinctDeviceOutput() throws {
    let renderedCards = try UsageCardColorScheme.allCases.map { colorScheme in
      try UsageCardRenderer.render(
        snapshot: .sample,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: colorScheme
      )
    }

    XCTAssertEqual(renderedCards.count, 6)
    XCTAssertEqual(Set(renderedCards.map(\.data)).count, renderedCards.count)
    XCTAssertTrue(renderedCards.allSatisfy { $0.pixelWidth == 142 && $0.pixelHeight == 428 })
  }

  @MainActor
  func testEveryLayoutProducesDistinctDeviceOutput() throws {
    let renderedCards = try UsageCardDesign.allCases.map { design in
      try UsageCardRenderer.render(
        snapshot: .sample,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: .deepSpace,
        design: design
      )
    }

    XCTAssertEqual(renderedCards.count, UsageCardDesign.allCases.count)
    XCTAssertEqual(Set(renderedCards.map(\.data)).count, renderedCards.count)
    XCTAssertTrue(renderedCards.allSatisfy { $0.pixelWidth == 142 && $0.pixelHeight == 428 })
  }

  @MainActor
  func testEveryClaudeLayoutProducesDistinctDeviceOutput() throws {
    let renderedCards = try UsageCardDesign.allCases.map { design in
      try UsageCardRenderer.render(
        claudeSnapshot: .sample,
        activityState: .running,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: .deepSpace,
        design: design
      )
    }

    XCTAssertEqual(renderedCards.count, UsageCardDesign.allCases.count)
    XCTAssertEqual(Set(renderedCards.map(\.data)).count, renderedCards.count)
    XCTAssertTrue(renderedCards.allSatisfy { $0.pixelWidth == 142 && $0.pixelHeight == 428 })
    XCTAssertTrue(renderedCards.allSatisfy { $0.data.count <= 512 * 1_024 })
  }

  @MainActor
  func testEveryGrokLayoutProducesDistinctDeviceOutput() throws {
    let renderedCards = try UsageCardDesign.allCases.map { design in
      try UsageCardRenderer.render(
        grokSnapshot: .sample,
        activityState: .running,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: .deepSpace,
        design: design
      )
    }

    XCTAssertEqual(renderedCards.count, UsageCardDesign.allCases.count)
    XCTAssertEqual(Set(renderedCards.map(\.data)).count, renderedCards.count)
    XCTAssertTrue(renderedCards.allSatisfy { $0.pixelWidth == 142 && $0.pixelHeight == 428 })
    XCTAssertTrue(renderedCards.allSatisfy { $0.data.count <= 512 * 1_024 })
  }

  @MainActor
  func testGrokLayoutsHandleMissingSnapshotAndLowRemaining() throws {
    let emptyRemaining = GrokUsageSnapshot(
      remainingPercent: 0,
      usedPercent: 100,
      periodType: .weekly,
      periodStart: Date(),
      periodEnd: Date().addingTimeInterval(86_400),
      subscriptionTier: "GrokPro",
      prepaidBalance: 0,
      onDemandUsed: 0,
      onDemandCap: 0
    )

    for design in UsageCardDesign.allCases {
      let populated = try UsageCardRenderer.render(
        grokSnapshot: emptyRemaining,
        activityState: .running,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        design: design
      )
      let waiting = try UsageCardRenderer.render(
        grokSnapshot: nil,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        design: design
      )
      let remaining = try UsageCardRenderer.render(
        grokSnapshot: .sample,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        design: design
      )

      XCTAssertEqual(populated.pixelWidth, 142)
      XCTAssertEqual(populated.pixelHeight, 428)
      XCTAssertLessThanOrEqual(populated.data.count, 512 * 1_024)
      XCTAssertNotEqual(populated.data, waiting.data)
      XCTAssertNotEqual(remaining.data, populated.data)
    }
  }

  @MainActor
  func testEveryQoderLayoutProducesDistinctDeviceOutput() throws {
    let renderedCards = try UsageCardDesign.allCases.map { design in
      try UsageCardRenderer.render(
        qoderSnapshot: .sample,
        creditSnapshot: .sample,
        activityState: .awaitingAuthorization,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: .deepSpace,
        design: design
      )
    }

    XCTAssertEqual(renderedCards.count, UsageCardDesign.allCases.count)
    XCTAssertEqual(Set(renderedCards.map(\.data)).count, renderedCards.count)
    XCTAssertTrue(renderedCards.allSatisfy { $0.pixelWidth == 142 && $0.pixelHeight == 428 })
    XCTAssertTrue(renderedCards.allSatisfy { $0.data.count <= 512 * 1_024 })
  }

  @MainActor
  func testEveryQoderColorAndLayoutCombinationRendersWithinLimits() throws {
    for colorScheme in UsageCardColorScheme.allCases {
      for design in UsageCardDesign.allCases {
        let rendered = try UsageCardRenderer.render(
          qoderSnapshot: .sample,
          creditSnapshot: .sample,
          activityState: .running,
          safeAreaHeight: UsageCardLayout.maximumSafeArea,
          jpegQuality: 0.9,
          colorScheme: colorScheme,
          design: design
        )

        XCTAssertEqual(rendered.pixelWidth, 142)
        XCTAssertEqual(rendered.pixelHeight, 428)
        XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)
      }
    }
  }

  @MainActor
  func testQoderLayoutsHandleMissingAndLargeValues() throws {
    let largeSnapshot = QoderUsageSnapshot(
      todayPrompts: 128_400,
      weekPrompts: 2_845_900,
      todaySessions: 12_000,
      todayToolCalls: 982_000,
      lastActiveDate: Date()
    )
    let largeCredit = QoderCreditSnapshot(
      userType: "personal_professional_trial",
      creditsUsed: 128_400,
      creditsTotal: 2_845_900,
      creditsRemaining: 2_717_500,
      usagePercentage: 0.045,
      isQuotaExceeded: false,
      contextUsedTokens: 198_500,
      contextLimitTokens: 200_000
    )

    for design in UsageCardDesign.allCases {
      let populated = try UsageCardRenderer.render(
        qoderSnapshot: largeSnapshot,
        creditSnapshot: largeCredit,
        activityState: .awaitingAuthorization,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        design: design
      )
      let waiting = try UsageCardRenderer.render(
        qoderSnapshot: nil,
        creditSnapshot: nil,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        design: design
      )

      XCTAssertEqual(populated.pixelWidth, 142)
      XCTAssertEqual(populated.pixelHeight, 428)
      XCTAssertLessThanOrEqual(populated.data.count, 512 * 1_024)
      XCTAssertEqual(waiting.pixelWidth, 142)
      XCTAssertEqual(waiting.pixelHeight, 428)
      XCTAssertNotEqual(populated.data, waiting.data)
    }
  }

  @MainActor
  func testEveryColorAndLayoutCombinationRendersWithinLimits() throws {
    for colorScheme in UsageCardColorScheme.allCases {
      for design in UsageCardDesign.allCases {
        let rendered = try UsageCardRenderer.render(
          snapshot: .sample,
          safeAreaHeight: UsageCardLayout.maximumSafeArea,
          jpegQuality: 0.9,
          colorScheme: colorScheme,
          design: design
        )
        XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)
        XCTAssertEqual(rendered.pixelWidth, 142)
        XCTAssertEqual(rendered.pixelHeight, 428)
      }
    }
  }

  @MainActor
  func testMinimalColumnContentRespondsToSafeAreaHeight() throws {
    let compactSafeArea = try UsageCardRenderer.render(
      snapshot: .sample,
      safeAreaHeight: UsageCardLayout.minimumSafeArea,
      jpegQuality: 0.9,
      colorScheme: .deepSpace,
      design: .minimalColumn
    )
    let expandedSafeArea = try UsageCardRenderer.render(
      snapshot: .sample,
      safeAreaHeight: UsageCardLayout.maximumSafeArea,
      jpegQuality: 0.9,
      colorScheme: .deepSpace,
      design: .minimalColumn
    )

    XCTAssertNotEqual(compactSafeArea.data, expandedSafeArea.data)
  }

  @MainActor
  func testMinimalColumnTrafficLightStatesProduceDistinctOutput() throws {
    let renderedStates = try [
      CodexActivityState.idle,
      .finished,
      .running,
      .awaitingAuthorization,
      .toolFailed,
    ].map { state in
      try UsageCardRenderer.render(
        snapshot: .sample,
        activityState: state,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: .deepSpace,
        design: .minimalColumn
      )
    }

    XCTAssertEqual(Set(renderedStates.map(\.data)).count, 5)
  }

  func testRemovedColorSchemesAreNoLongerAvailable() {
    XCTAssertNil(UsageCardColorScheme(rawValue: "quantumViolet"))
    XCTAssertNil(UsageCardColorScheme(rawValue: "matrixGreen"))
    XCTAssertNil(UsageCardColorScheme(rawValue: "mochaCircuit"))
  }

  @MainActor
  func testExperimentalStylesDoNotUseWhitePrimaryText() throws {
    for colorScheme in UsageCardColorScheme.allCases where colorScheme != .deepSpace {
      let color = try XCTUnwrap(
        NSColor(colorScheme.palette.primaryText).usingColorSpace(.deviceRGB)
      )
      let isNearWhite =
        color.redComponent > 0.9
        && color.greenComponent > 0.9
        && color.blueComponent > 0.9
      XCTAssertFalse(isNearWhite, "\(colorScheme.title) 不应继续使用白色主文字")
    }
  }

  @MainActor
  func testExperimentalStylesUseDistinctAccentAndPrimaryColors() throws {
    for colorScheme in UsageCardColorScheme.allCases where colorScheme != .deepSpace {
      let accent = try XCTUnwrap(NSColor(colorScheme.palette.accent).usingColorSpace(.deviceRGB))
      let primary = try XCTUnwrap(NSColor(colorScheme.palette.primaryText).usingColorSpace(.deviceRGB))
      let channelDistance =
        abs(accent.redComponent - primary.redComponent)
        + abs(accent.greenComponent - primary.greenComponent)
        + abs(accent.blueComponent - primary.blueComponent)

      XCTAssertGreaterThan(channelDistance, 0.35, "\(colorScheme.title) 的强调色与主文字应形成明显对比")
    }
  }

  @MainActor
  func testDeepSpacePaletteRemainsUnchanged() throws {
    let palette = UsageCardColorScheme.deepSpace.palette

    try assertColor(palette.background, equals: (8, 11, 18))
    try assertColor(palette.cardBackground, equals: (17, 24, 39))
    try assertColor(palette.insetBackground, equals: (11, 18, 32))
    try assertColor(palette.border, equals: (38, 52, 74))
    try assertColor(palette.accent, equals: (85, 230, 184))
    try assertColor(palette.primaryText, equals: (248, 250, 252))
    try assertColor(palette.secondaryText, equals: (148, 163, 184))
    try assertColor(palette.tertiaryText, equals: (100, 116, 139))
  }

  @MainActor
  func testAdjustedPantoneInspiredPalettes() throws {
    let aurora = UsageCardColorScheme.auroraBlue.palette
    try assertColor(aurora.background, equals: (14, 15, 35))
    try assertColor(aurora.accent, equals: (123, 130, 222))
    try assertColor(aurora.primaryText, equals: (218, 221, 250))

    let magenta = UsageCardColorScheme.fusionMagenta.palette
    try assertColor(magenta.background, equals: (23, 10, 17))
    try assertColor(magenta.accent, equals: (232, 82, 111))
    try assertColor(magenta.primaryText, equals: (240, 211, 219))

    let peach = UsageCardColorScheme.peachGlow.palette
    try assertColor(peach.background, equals: (27, 18, 15))
    try assertColor(peach.accent, equals: (255, 190, 152))
    try assertColor(peach.primaryText, equals: (235, 218, 207))
  }

  @MainActor
  func testProtectedPalettesRemainUnchanged() throws {
    let cloud = UsageCardColorScheme.cloudDancer.palette
    try assertColor(cloud.background, equals: (16, 20, 24))
    try assertColor(cloud.cardBackground, equals: (37, 43, 46))
    try assertColor(cloud.insetBackground, equals: (26, 32, 35))
    try assertColor(cloud.border, equals: (89, 97, 102))
    try assertColor(cloud.accent, equals: (240, 238, 233))
    try assertColor(cloud.primaryText, equals: (168, 216, 234))
    try assertColor(cloud.secondaryText, equals: (143, 209, 195))
    try assertColor(cloud.tertiaryText, equals: (156, 166, 167))

    let signal = UsageCardColorScheme.signalYellow.palette
    try assertColor(signal.background, equals: (17, 18, 19))
    try assertColor(signal.cardBackground, equals: (41, 43, 45))
    try assertColor(signal.insetBackground, equals: (29, 31, 32))
    try assertColor(signal.border, equals: (94, 96, 98))
    try assertColor(signal.accent, equals: (245, 223, 77))
    try assertColor(signal.primaryText, equals: (190, 192, 194))
    try assertColor(signal.secondaryText, equals: (245, 235, 174))
    try assertColor(signal.tertiaryText, equals: (147, 149, 151))
  }

  func testDefaultSafeAreaLeavesRoomForFirmwareStatusBar() {
    XCTAssertEqual(UsageCardLayout.defaultSafeArea, 56)
    XCTAssertGreaterThanOrEqual(UsageCardLayout.defaultSafeArea, UsageCardLayout.minimumSafeArea)
  }

  @MainActor
  private func assertColor(
    _ color: Color,
    equals expected: (red: CGFloat, green: CGFloat, blue: CGFloat),
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let converted = try XCTUnwrap(
      NSColor(color).usingColorSpace(.deviceRGB),
      file: file,
      line: line
    )
    XCTAssertEqual(converted.redComponent * 255, expected.red, accuracy: 0.01, file: file, line: line)
    XCTAssertEqual(converted.greenComponent * 255, expected.green, accuracy: 0.01, file: file, line: line)
    XCTAssertEqual(converted.blueComponent * 255, expected.blue, accuracy: 0.01, file: file, line: line)
  }

  @MainActor
  func testCustomImageIsCroppedToDeviceSizeWithDarkSafeArea() throws {
    let source = NSImage(size: NSSize(width: 320, height: 180))
    source.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 320, height: 180).fill()
    source.unlockFocus()

    let rendered = try CustomImageRenderer.render(
      image: source,
      safeAreaHeight: UsageCardLayout.defaultSafeArea,
      jpegQuality: 0.9
    )

    XCTAssertEqual(rendered.pixelWidth, 142)
    XCTAssertEqual(rendered.pixelHeight, 428)
    XCTAssertLessThanOrEqual(rendered.data.count, 512 * 1_024)
    XCTAssertEqual(rendered.image.size, NSSize(width: 142, height: 428))
    XCTAssertEqual(rendered.image.representations.first?.pixelsWide, 284)
    XCTAssertEqual(rendered.image.representations.first?.pixelsHigh, 856)

    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.data))
    let safeAreaColor = try XCTUnwrap(bitmap.colorAt(x: 71, y: 10)?.usingColorSpace(.deviceRGB))
    let contentColor = try XCTUnwrap(bitmap.colorAt(x: 71, y: 200)?.usingColorSpace(.deviceRGB))
    XCTAssertLessThan(safeAreaColor.redComponent, 0.1)
    XCTAssertGreaterThan(contentColor.redComponent, 0.7)
  }
}
