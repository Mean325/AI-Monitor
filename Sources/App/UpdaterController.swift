import Foundation
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
  func checkForUpdates()
}

@MainActor
final class UpdaterController: UpdateChecking {
  private let controller: SPUStandardUpdaterController

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
