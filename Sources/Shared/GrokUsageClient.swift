import Foundation

protocol GrokUsageFetching: Sendable {
  func fetch() async throws -> GrokUsageSnapshot
}

enum GrokClientError: LocalizedError, Equatable {
  case authFileMissing
  case authInvalid
  case tokenExpired
  case timedOut
  case unauthorized
  case server(Int, String)
  case invalidResponse
  case network(String)

  var errorDescription: String? {
    switch self {
    case .authFileMissing:
      return "未找到 Grok 登录信息（~/.grok/auth.json），请先运行 grok login。"
    case .authInvalid:
      return "Grok 登录文件无法解析，请重新运行 grok login。"
    case .tokenExpired:
      return "Grok 登录已过期，请运行 grok login。"
    case .timedOut:
      return "读取 Grok 余量超时。"
    case .unauthorized:
      return "Grok 拒绝了用量查询，请运行 grok login。"
    case .server(let status, let message):
      return "Grok 用量接口返回 HTTP \(status)：\(message)"
    case .invalidResponse:
      return "Grok 返回了无法识别的余量数据。"
    case .network(let message):
      return "读取 Grok 余量失败：\(message)"
    }
  }
}

final class GrokUsageClient: GrokUsageFetching, @unchecked Sendable {
  private let authURL: URL
  private let billingURL: URL
  private let userURL: URL
  private let tokenURL: URL
  private let session: URLSession
  private let now: () -> Date

  init(
    authURL: URL? = nil,
    billingURL: URL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
    userURL: URL = URL(string: "https://cli-chat-proxy.grok.com/v1/user?include=subscription")!,
    tokenURL: URL = URL(string: "https://auth.x.ai/oauth2/token")!,
    session: URLSession = .shared,
    now: @escaping () -> Date = { Date() }
  ) {
    if let authURL {
      self.authURL = authURL
    } else if let override = ProcessInfo.processInfo.environment["GROK_AUTH_PATH"],
      !override.isEmpty
    {
      self.authURL = URL(fileURLWithPath: override)
    } else {
      self.authURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/auth.json")
    }
    self.billingURL = billingURL
    self.userURL = userURL
    self.tokenURL = tokenURL
    self.session = session
    self.now = now
  }

  func fetch() async throws -> GrokUsageSnapshot {
    try await Task.detached(priority: .utility) {
      try self.fetchBlocking()
    }.value
  }

  func fetchSynchronously() throws -> GrokUsageSnapshot {
    try fetchBlocking()
  }

  static func makeSnapshot(
    billingData: Data,
    userData: Data? = nil
  ) throws -> GrokUsageSnapshot {
    let billing = try JSONDecoder().decode(GrokBillingEnvelope.self, from: billingData)
    guard let config = billing.config else {
      throw GrokClientError.invalidResponse
    }

    let usedPercent = resolvedUsedPercent(from: config)
    guard let usedPercent else {
      throw GrokClientError.invalidResponse
    }

    let remainingPercent = max(0, min(100, Int((100 - usedPercent).rounded())))
    let period = config.currentPeriod
    let periodType = GrokUsagePeriodType(apiValue: period?.type)
    let periodStart = parseDate(period?.start) ?? parseDate(config.billingPeriodStart)
    let periodEnd = parseDate(period?.end) ?? parseDate(config.billingPeriodEnd)

    var subscriptionTier: String?
    if let userData,
      let user = try? JSONDecoder().decode(GrokUserEnvelope.self, from: userData)
    {
      subscriptionTier = user.subscriptionTier
    }

    return GrokUsageSnapshot(
      remainingPercent: remainingPercent,
      usedPercent: usedPercent,
      periodType: periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
      subscriptionTier: subscriptionTier,
      prepaidBalance: config.prepaidBalance?.intValue ?? 0,
      onDemandUsed: config.onDemandUsed?.intValue ?? 0,
      onDemandCap: config.onDemandCap?.intValue ?? 0
    )
  }

  private func fetchBlocking() throws -> GrokUsageSnapshot {
    var credential = try loadCredential()
    if credential.needsRefresh(at: now()) {
      credential = try refresh(credential)
    }

    do {
      return try fetchSnapshot(using: credential.accessToken)
    } catch GrokClientError.unauthorized {
      let refreshed = try refresh(credential)
      return try fetchSnapshot(using: refreshed.accessToken)
    }
  }

  private func fetchSnapshot(using accessToken: String) throws -> GrokUsageSnapshot {
    let billingData = try sendJSON(url: billingURL, accessToken: accessToken)
    let userData = try? sendJSON(url: userURL, accessToken: accessToken)
    return try Self.makeSnapshot(billingData: billingData, userData: userData)
  }

  private func sendJSON(url: URL, accessToken: String) throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexLinxDisplay/0.2.0", forHTTPHeaderField: "User-Agent")

    let (data, response) = try send(request)
    switch response.statusCode {
    case 200...299:
      return data
    case 401, 403:
      throw GrokClientError.unauthorized
    default:
      let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw GrokClientError.server(
        response.statusCode,
        message.isEmpty ? "未知错误" : String(message.prefix(180))
      )
    }
  }

  private func refresh(_ credential: GrokAuthCredential) throws -> GrokAuthCredential {
    guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty,
      let clientId = credential.clientId, !clientId.isEmpty
    else {
      throw GrokClientError.tokenExpired
    }

    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.setValue("CodexLinxDisplay/0.2.0", forHTTPHeaderField: "User-Agent")
    let body = [
      "grant_type=refresh_token",
      "refresh_token=\(urlEncoded(refreshToken))",
      "client_id=\(urlEncoded(clientId))",
    ].joined(separator: "&")
    request.httpBody = Data(body.utf8)

    let (data, response) = try send(request)
    guard (200...299).contains(response.statusCode) else {
      throw GrokClientError.tokenExpired
    }

    let token = try JSONDecoder().decode(GrokRefreshResponse.self, from: data)
    guard let accessToken = token.accessToken, !accessToken.isEmpty else {
      throw GrokClientError.tokenExpired
    }

    let expiresAt: Date
    if let expiresIn = token.expiresIn, expiresIn > 0 {
      expiresAt = now().addingTimeInterval(TimeInterval(expiresIn))
    } else {
      expiresAt = now().addingTimeInterval(6 * 60 * 60)
    }

    let updated = GrokAuthCredential(
      profileKey: credential.profileKey,
      accessToken: accessToken,
      refreshToken: token.refreshToken ?? refreshToken,
      expiresAt: expiresAt,
      clientId: clientId,
      rawProfile: credential.rawProfile
    )
    try persist(updated)
    return updated
  }

  private func loadCredential() throws -> GrokAuthCredential {
    guard FileManager.default.fileExists(atPath: authURL.path) else {
      throw GrokClientError.authFileMissing
    }
    let data: Data
    do {
      data = try Data(contentsOf: authURL)
    } catch {
      throw GrokClientError.authInvalid
    }
    return try Self.parseCredential(from: data)
  }

  static func parseCredential(from data: Data) throws -> GrokAuthCredential {
    guard
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      !object.isEmpty
    else {
      throw GrokClientError.authInvalid
    }

    var best: GrokAuthCredential?
    for (key, value) in object {
      guard let profile = value as? [String: Any] else { continue }
      guard let accessToken = profile["key"] as? String, !accessToken.isEmpty else { continue }
      let credential = GrokAuthCredential(
        profileKey: key,
        accessToken: accessToken,
        refreshToken: profile["refresh_token"] as? String,
        expiresAt: parseDate(profile["expires_at"] as? String),
        clientId: (profile["oidc_client_id"] as? String)
          ?? clientId(fromProfileKey: key),
        rawProfile: profile
      )
      if best == nil || credential.isFresher(than: best!) {
        best = credential
      }
    }

    guard let best else {
      throw GrokClientError.authInvalid
    }
    return best
  }

  private func persist(_ credential: GrokAuthCredential) throws {
    var root: [String: Any] = [:]
    if let data = try? Data(contentsOf: authURL),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      root = object
    }

    var profile = credential.rawProfile
    profile["key"] = credential.accessToken
    if let refreshToken = credential.refreshToken {
      profile["refresh_token"] = refreshToken
    }
    if let expiresAt = credential.expiresAt {
      profile["expires_at"] = isoFormatter.string(from: expiresAt)
    }
    root[credential.profileKey] = profile

    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    try data.write(to: authURL, options: .atomic)
  }

  private func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    let semaphore = DispatchSemaphore(value: 0)
    var capturedData: Data?
    var capturedResponse: URLResponse?
    var capturedError: Error?

    let task = session.dataTask(with: request) { data, response, error in
      capturedData = data
      capturedResponse = response
      capturedError = error
      semaphore.signal()
    }
    task.resume()

    if semaphore.wait(timeout: .now() + 20) == .timedOut {
      task.cancel()
      throw GrokClientError.timedOut
    }

    if let capturedError {
      throw GrokClientError.network(capturedError.localizedDescription)
    }
    guard let http = capturedResponse as? HTTPURLResponse else {
      throw GrokClientError.invalidResponse
    }
    return (capturedData ?? Data(), http)
  }

  private static func resolvedUsedPercent(from config: GrokBillingConfig) -> Double? {
    if let product = config.productUsage?.first(where: {
      ($0.product ?? "").caseInsensitiveCompare("GrokBuild") == .orderedSame
    }), let percent = product.usagePercent {
      return percent
    }
    if let percent = config.productUsage?.first?.usagePercent {
      return percent
    }
    if let percent = config.creditUsagePercent {
      return percent
    }

    // Grok omits usage percentage fields when the current period has no usage.
    // A period in the response confirms this is a valid billing payload rather
    // than an unrelated or malformed `config` object.
    if config.currentPeriod != nil
      || config.billingPeriodStart != nil
      || config.billingPeriodEnd != nil
    {
      return 0
    }
    return nil
  }

  private static func clientId(fromProfileKey key: String) -> String? {
    let parts = key.split(separator: "::", maxSplits: 1).map(String.init)
    return parts.count == 2 ? parts[1] : nil
  }

  private static func parseDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    if let date = fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) {
      return date
    }
    return isoFormatter.date(from: string)
  }

  private func urlEncoded(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

struct GrokAuthCredential: Equatable {
  let profileKey: String
  let accessToken: String
  let refreshToken: String?
  let expiresAt: Date?
  let clientId: String?
  let rawProfile: [String: Any]

  static func == (lhs: GrokAuthCredential, rhs: GrokAuthCredential) -> Bool {
    lhs.profileKey == rhs.profileKey
      && lhs.accessToken == rhs.accessToken
      && lhs.refreshToken == rhs.refreshToken
      && lhs.expiresAt == rhs.expiresAt
      && lhs.clientId == rhs.clientId
  }

  func needsRefresh(at now: Date) -> Bool {
    guard refreshToken != nil else { return false }
    guard let expiresAt else { return false }
    return expiresAt.addingTimeInterval(-60) <= now
  }

  func isFresher(than other: GrokAuthCredential) -> Bool {
    switch (expiresAt, other.expiresAt) {
    case let (lhs?, rhs?):
      return lhs > rhs
    case (_?, nil):
      return true
    default:
      return false
    }
  }
}

private struct GrokBillingEnvelope: Decodable {
  let config: GrokBillingConfig?
}

private struct GrokBillingConfig: Decodable {
  let currentPeriod: GrokBillingPeriod?
  let creditUsagePercent: Double?
  let productUsage: [GrokProductUsage]?
  let prepaidBalance: GrokNumericValue?
  let onDemandCap: GrokNumericValue?
  let onDemandUsed: GrokNumericValue?
  let billingPeriodStart: String?
  let billingPeriodEnd: String?
}

private struct GrokBillingPeriod: Decodable {
  let type: String?
  let start: String?
  let end: String?
}

private struct GrokProductUsage: Decodable {
  let product: String?
  let usagePercent: Double?
}

private struct GrokNumericValue: Decodable {
  let val: Double?

  var intValue: Int { Int((val ?? 0).rounded()) }
}

private struct GrokUserEnvelope: Decodable {
  let subscriptionTier: String?
}

private struct GrokRefreshResponse: Decodable {
  let accessToken: String?
  let refreshToken: String?
  let expiresIn: Int?

  private enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
  }
}

private extension GrokUsagePeriodType {
  init(apiValue: String?) {
    switch apiValue {
    case "USAGE_PERIOD_TYPE_DAILY", "DAILY", "daily":
      self = .daily
    case "USAGE_PERIOD_TYPE_WEEKLY", "WEEKLY", "weekly":
      self = .weekly
    case "USAGE_PERIOD_TYPE_MONTHLY", "MONTHLY", "monthly":
      self = .monthly
    default:
      self = .unknown
    }
  }
}

private let fractionalFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

private let plainFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

private let isoFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()
