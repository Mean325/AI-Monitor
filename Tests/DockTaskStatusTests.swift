import AppKit
import XCTest
@testable import CodexLinxDisplay

final class DockTaskStatusTests: XCTestCase {
  @MainActor
  func testPreferenceDefaultsOffAndPersistsAcrossLaunches() throws {
    let suite = "DockTaskStatusTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "linxEnabled")
    let model = AppModel(defaults: defaults)
    XCTAssertFalse(model.showTaskStatusInDock)
    model.showTaskStatusInDock = true
    XCTAssertTrue(AppModel(defaults: defaults).showTaskStatusInDock)
    model.showTaskStatusInDock = false
    XCTAssertFalse(AppModel(defaults: defaults).showTaskStatusInDock)
  }

  func testArtworkIncludesShadowOutsideTheBackground() throws {
    for dark in [false, true] {
      let image = DockTaskStatusIcon.makeImage(state: .running, darkAppearance: dark)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
      let alpha = try [22, 490].map { y in
        try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2,
          y: y * bitmap.pixelsHigh / 512)).alphaComponent
      }.max() ?? 0
      XCTAssertGreaterThan(alpha, 0.01, "The custom Dock tile must carry its own shadow")
      XCTAssertLessThan(alpha, 0.7)
    }
  }

  func testStatusLensAndBezelRemainVisibleInBothAppearances() throws {
    for dark in [false, true] {
      for state in [CodexActivityState.idle, .finished, .running,
                    .awaitingAuthorization, .toolFailed, .quotaExhausted] {
        let image = DockTaskStatusIcon.makeImage(state: state, darkAppearance: dark)
        XCTAssertFalse(image.isTemplate)
        // The Dock must receive finished pixels, not a lazy drawing handler
        // that can be rendered differently in its own graphics context.
        XCTAssertFalse(image.representations.isEmpty)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        func color(x: CGFloat) throws -> NSColor {
          try XCTUnwrap(bitmap.colorAt(
            x: Int(x * CGFloat(bitmap.pixelsWide) / 512), y: bitmap.pixelsHigh / 2
          )?.usingColorSpace(.sRGB))
        }
        let background = try color(x: 48)
        XCTAssertEqual(background.redComponent, dark ? 0 : 1, accuracy: 0.02)
        let bezel = try color(x: 90)
        XCTAssertGreaterThan(bezel.redComponent, 0.01)
        XCTAssertLessThan(bezel.redComponent, 0.6)
        XCTAssertGreaterThan(bezel.alphaComponent, 0.95)
        XCTAssertEqual(bezel.greenComponent, bezel.redComponent, accuracy: 0.02)
        let lens = try color(x: 256)
        switch state {
        case .idle, .finished:
          XCTAssertGreaterThan(lens.greenComponent, lens.redComponent)
        case .running:
          XCTAssertGreaterThan(lens.redComponent, lens.greenComponent)
          XCTAssertGreaterThan(lens.greenComponent, lens.blueComponent)
        case .awaitingAuthorization, .toolFailed, .quotaExhausted:
          XCTAssertGreaterThan(lens.redComponent, lens.greenComponent)
        }
      }
    }
  }
}
