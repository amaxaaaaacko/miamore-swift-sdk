import Foundation

@MainActor
public enum MiaMoreSDK {
  public static let version = "0.1.2"

  public struct Configuration: Sendable {
    public let baseURL: URL
    public let bundleId: String
    public let apiKey: String
    public let customerUserId: String
    public let environment: MiaMoreEnvironment
    public let logLevel: MiaMoreLogLevel

    public init(
      baseURL: URL,
      bundleId: String,
      apiKey: String,
      customerUserId: String,
      environment: MiaMoreEnvironment,
      logLevel: MiaMoreLogLevel
    ) {
      self.baseURL = baseURL
      self.bundleId = bundleId
      self.apiKey = apiKey
      self.customerUserId = customerUserId
      self.environment = environment
      self.logLevel = logLevel
    }
  }

  public enum SDKError: Error {
    case notConfigured
    case invalidBaseURL
    case invalidResponse
    case httpError(status: Int, body: String?)
  }

  private static var config: Configuration?

  /// Configure SDK once at app launch.
  ///
  /// - Parameters:
  ///   - baseURL: SDK config API base URL, e.g. https://appstore-sdk-...a.run.app
  ///   - bundleId: Your app bundle id (used as app key in backend), e.g. com.my.app
  ///   - apiKey: Per-app SDK API key (from AdminJS)
  ///   - customerUserId: AppsFlyer-generated user id, passed from app
  ///   - environment: PROD / SANDBOX (default: PROD)
  ///   - logLevel: debug/info/... (default: info)
  public static func configure(
    baseURL: URL,
    bundleId: String,
    apiKey: String,
    customerUserId: String,
    environment: MiaMoreEnvironment = .prod,
    logLevel: MiaMoreLogLevel = .info
  ) {
    config = Configuration(
      baseURL: baseURL,
      bundleId: bundleId,
      apiKey: apiKey,
      customerUserId: customerUserId,
      environment: environment,
      logLevel: logLevel
    )
  }

  public static var configuration: Configuration? {
    config
  }

  public struct ProductRef: Codable, Sendable {
    public let productId: String
    public let sort: Int?

    enum CodingKeys: String, CodingKey {
      case productId = "product_id"
      case sort
    }
  }

  public struct Paywall: Codable, Sendable {
    public let paywallId: String
    public let name: String
    public let products: [ProductRef]

    enum CodingKeys: String, CodingKey {
      case paywallId = "paywall_id"
      case name
      case products
    }
  }

  public struct Assignment: Codable, Sendable {
    public let experimentId: String
    public let variantId: String
    public let bucket: Int

    enum CodingKeys: String, CodingKey {
      case experimentId = "experiment_id"
      case variantId = "variant_id"
      case bucket
    }
  }

  public struct PaywallResponse: Codable, Sendable {
    public let appBundleId: String
    public let customerUserId: String
    public let placement: String?
    public let assignment: Assignment?
    public let paywall: Paywall

    enum CodingKeys: String, CodingKey {
      case appBundleId = "app_bundle_id"
      case customerUserId = "customer_user_id"
      case placement
      case assignment
      case paywall
    }
  }

  /// Fetch paywall for given placement (recommended).
  public static func getPaywall(placement: String) async throws -> PaywallResponse {
    try await getPaywall(placement: placement, paywallId: nil, experimentId: nil)
  }

  /// Advanced: fetch paywall by id or experiment id.
  public static func getPaywall(placement: String?, paywallId: String?, experimentId: String?) async throws -> PaywallResponse {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(
      baseURL: cfg.baseURL,
      path: "/v1/sdk/paywall",
      query: [
        URLQueryItem(name: "bundleId", value: cfg.bundleId),
        URLQueryItem(name: "customerUserId", value: cfg.customerUserId),
        URLQueryItem(name: "placement", value: placement),
        URLQueryItem(name: "paywallId", value: paywallId),
        URLQueryItem(name: "experimentId", value: experimentId),
      ].compactMap { item in
        guard let v = item.value, !v.isEmpty else { return nil }
        return item
      }
    )

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw SDKError.invalidResponse }

    if http.statusCode >= 300 {
      let body = String(data: data, encoding: .utf8)
      throw SDKError.httpError(status: http.statusCode, body: body)
    }

    let decoder = JSONDecoder()
    return try decoder.decode(PaywallResponse.self, from: data)
  }
}
