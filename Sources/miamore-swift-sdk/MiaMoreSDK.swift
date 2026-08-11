import Foundation

private let miaMoreAppAccountTokenDefaultsKey = "com.miamore.sdk.appAccountToken"

private func loadOrCreateMiaMoreAppAccountToken() -> UUID {
  let defaults = UserDefaults.standard
  if let raw = defaults.string(forKey: miaMoreAppAccountTokenDefaultsKey), let uuid = UUID(uuidString: raw) {
    return uuid
  }
  let uuid = UUID()
  defaults.set(uuid.uuidString, forKey: miaMoreAppAccountTokenDefaultsKey)
  return uuid
}

@MainActor
public enum MiaMoreSDK {
  public static let version = "0.1.10"

  public struct Configuration: Sendable {
    public let baseURL: URL
    public let bundleId: String
    public let apiKey: String
    public let customerUserId: String
    /// Stable UUID attached to StoreKit purchases as `appAccountToken`.
    /// Keep this distinct from AppsFlyer-style customer ids such as `177...-...`.
    public let appAccountToken: UUID
    public let environment: MiaMoreEnvironment
    public let logLevel: MiaMoreLogLevel

    public init(
      baseURL: URL,
      bundleId: String,
      apiKey: String,
      customerUserId: String,
      appAccountToken: UUID? = nil,
      environment: MiaMoreEnvironment,
      logLevel: MiaMoreLogLevel
    ) {
      self.baseURL = baseURL
      self.bundleId = bundleId
      self.apiKey = apiKey
      self.customerUserId = customerUserId
      self.appAccountToken = appAccountToken ?? loadOrCreateMiaMoreAppAccountToken()
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
  ///   - appAccountToken: Stable UUID attached to StoreKit purchases. If omitted, SDK creates and stores one locally.
  ///   - environment: PROD / SANDBOX (default: PROD)
  ///   - logLevel: debug/info/... (default: info)
  public static func configure(
    baseURL: URL,
    bundleId: String,
    apiKey: String,
    customerUserId: String,
    appAccountToken: UUID? = nil,
    environment: MiaMoreEnvironment = .prod,
    logLevel: MiaMoreLogLevel = .info
  ) {
    config = Configuration(
      baseURL: baseURL,
      bundleId: bundleId,
      apiKey: apiKey,
      customerUserId: customerUserId,
      appAccountToken: appAccountToken ?? loadOrCreateMiaMoreAppAccountToken(),
      environment: environment,
      logLevel: logLevel
    )

    // Auto-track basic activity for refund-saver heuristics.
    MiaMoreAppOpenAutoTracker.shared.startIfNeeded()

    // StoreKit recommends listening for Transaction.updates at app launch so
    // async/deferred successful purchases are not missed. This is safe to start
    // multiple times; the SDK keeps a single listener task per process.
    #if canImport(StoreKit)
    startTransactionUpdatesListenerIfNeeded()
    #endif
  }

  public static var configuration: Configuration? {
    config
  }

  public enum BillingPlanType: String, Codable, Sendable {
    /// Standard auto-renewable subscription billing: the customer pays for the whole billing period up front.
    case upFront = "up_front"

    /// Monthly billing for a yearly commitment plan.
    case monthlyCommitment = "monthly"

    /// Unknown/future billing plan value returned by backend or Apple.
    case unknown = "unknown"

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "up_front", "upfront", "billed_upfront", "billed-upfront":
        self = .upFront
      case "monthly", "monthly_commitment", "monthly-commitment":
        self = .monthlyCommitment
      default:
        self = .unknown
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  public struct ProductRef: Codable, Sendable {
    public let productId: String
    public let sort: Int?
    /// Optional billing plan selector for products that expose multiple billing options under the same product id.
    /// `nil` means the app should use StoreKit's default/up-front billing plan.
    public let billingPlanType: BillingPlanType?

    enum CodingKeys: String, CodingKey {
      case productId = "product_id"
      case sort
      case billingPlanType = "billing_plan_type"
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

  public struct VariantAssignment: Codable, Sendable {
    public let experimentId: String
    public let variantAbTestId: String
    public let variantId: String
    public let bucket: Int
    public let totalWeight: Double?

    enum CodingKeys: String, CodingKey {
      case experimentId = "experiment_id"
      case variantAbTestId = "variant_ab_test_id"
      case variantId = "variant_id"
      case bucket
      case totalWeight = "total_weight"
    }
  }

  public struct VariantResponse: Codable, Sendable {
    public let appBundleId: String
    public let customerUserId: String
    public let variantAbTestId: String
    public let assignment: VariantAssignment
    public let variantId: String

    enum CodingKeys: String, CodingKey {
      case appBundleId = "app_bundle_id"
      case customerUserId = "customer_user_id"
      case variantAbTestId = "variant_ab_test_id"
      case assignment
      case variantId = "variant_id"
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

  /// Fetch a deterministic custom string variant for a Variant A/B Test.
  public static func getVariant(_ variantTestId: String) async throws -> VariantResponse {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(
      baseURL: cfg.baseURL,
      path: "/v1/sdk/variant",
      query: [
        URLQueryItem(name: "bundleId", value: cfg.bundleId),
        URLQueryItem(name: "customerUserId", value: cfg.customerUserId),
        URLQueryItem(name: "variantTestId", value: variantTestId),
      ]
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
    return try decoder.decode(VariantResponse.self, from: data)
  }
}
