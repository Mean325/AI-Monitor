import AppKit
import Foundation
import Network

enum LocalNetworkAccess {
  /// Kick the Local Network alert before the JPEG upload, and bring the
  /// agent app forward so the system dialog is not buried.
  static func preflight(endpoint: String) async {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    guard let url = URL(string: endpoint), let host = url.host, !host.isEmpty else { return }

    await MainActor.run {
      NSApp.unhide(nil)
      NSApp.activate(ignoringOtherApps: true)
    }

    let portValue = UInt16(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))
    guard let port = NWEndpoint.Port(rawValue: portValue) else { return }

    let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let resume = ResumeOnce(continuation)
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready, .failed, .cancelled:
          resume.run()
        default:
          break
        }
      }
      connection.start(queue: .global(qos: .utility))
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
        resume.run()
      }
    }
    connection.cancel()
  }
}

private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var didResume = false
  private let continuation: CheckedContinuation<Void, Never>

  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  func run() {
    lock.lock()
    defer { lock.unlock() }
    guard !didResume else { return }
    didResume = true
    continuation.resume()
  }
}
