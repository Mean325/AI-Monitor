import Foundation

protocol ImageUploading: Sendable {
  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult
}

enum ImageAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case connectionFailed
  case timedOut
  case networkUnavailable
  case transport(String)
  case rejected(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "图像 API 地址无效。"
    case .invalidResponse:
      return "图像 API 没有返回有效的 HTTP 响应。"
    case .connectionFailed:
      return "无法连接键盘，请确认设备在线且 API 地址正确。"
    case .timedOut:
      return "连接键盘超时，请检查局域网和设备地址。"
    case .networkUnavailable:
      return "当前无法访问局域网；首次运行时请允许“本地网络”权限。"
    case .transport(let message):
      return "图像上传失败：\(message)"
    case .rejected(let code, let message):
      return message.isEmpty ? "图像 API 返回 HTTP \(code)。" : "图像 API 返回 HTTP \(code)：\(message)"
    }
  }

  var isTransientLocalNetwork: Bool {
    switch self {
    case .networkUnavailable, .timedOut:
      return true
    default:
      return false
    }
  }
}

struct ImageUploadResult: Sendable {
  let statusCode: Int
  let responseText: String
}

struct ImageAPIClient: ImageUploading {
  private let session: URLSession

  init(session: URLSession = ImageAPIClient.makeSession()) {
    self.session = session
  }

  /// Local Network TCC denies the first LAN request immediately while the
  /// Allow dialog is up (TN3179). `waitsForConnectivity` keeps that request
  /// parked until the path is allowed, instead of failing as -1009.
  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration)
  }

  func upload(_ imageData: Data, endpoint: String) async throws -> ImageUploadResult {
    guard let url = URL(string: endpoint),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else {
      throw ImageAPIError.invalidURL
    }

    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = imageData

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw mapUploadError(error)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ImageAPIError.invalidResponse
    }

    let responseText =
      String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw ImageAPIError.rejected(httpResponse.statusCode, responseText)
    }

    return ImageUploadResult(statusCode: httpResponse.statusCode, responseText: responseText)
  }

  private func mapUploadError(_ error: Error) -> ImageAPIError {
    if isLocalNetworkPrivacyFailure(error) {
      return .networkUnavailable
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost:
        return .connectionFailed
      case .timedOut:
        return .timedOut
      default:
        return .transport(urlError.localizedDescription)
      }
    }
    return .transport(error.localizedDescription)
  }
}

private func isLocalNetworkPrivacyFailure(_ error: Error) -> Bool {
  var current: Error? = error
  while let err = current {
    let ns = err as NSError
    if ns.domain == NSPOSIXErrorDomain, ns.code == 50 || ns.code == 51 {
      return true
    }
    if ns.domain == NSURLErrorDomain {
      switch URLError.Code(rawValue: ns.code) {
      case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
        return true
      default:
        break
      }
    }
    current = ns.userInfo[NSUnderlyingErrorKey] as? Error
  }
  return false
}
