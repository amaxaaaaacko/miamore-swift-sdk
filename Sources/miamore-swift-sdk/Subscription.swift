import Foundation

extension MiaMoreSDK {
  /// Fetch subscription status from MiaMore backend.
  /// Requires that the user has been linked to Apple `original_transaction_id`.
  public static func getSubscriptionStatus() async throws -> MiaMoreSubscriptionStatus {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(
      baseURL: cfg.baseURL,
      path: "/v1/sdk/subscriptionStatus",
      query: [
        URLQueryItem(name: "bundleId", value: cfg.bundleId),
        URLQueryItem(name: "customerUserId", value: cfg.customerUserId),
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
    MiaMoreHTTP.decodeISODate(decoder)

    return try decoder.decode(MiaMoreSubscriptionStatus.self, from: data)
  }

  /// Link AppsFlyer `customerUserId` to Apple `original_transaction_id`.
  /// Call this once you know `originalTransactionId`.
  public static func link(originalTransactionId: String, environment: MiaMoreEnvironment? = nil) async throws {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(
      baseURL: cfg.baseURL,
      path: "/v1/sdk/link",
      query: []
    )

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    let body: [String: Any] = [
      "bundleId": cfg.bundleId,
      "customerUserId": cfg.customerUserId,
      "environment": (environment ?? cfg.environment).rawValue,
      "originalTransactionId": originalTransactionId,
    ]

    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw SDKError.invalidResponse }

    if http.statusCode >= 300 {
      let bodyStr = String(data: data, encoding: .utf8)
      throw SDKError.httpError(status: http.statusCode, body: bodyStr)
    }
  }
}
