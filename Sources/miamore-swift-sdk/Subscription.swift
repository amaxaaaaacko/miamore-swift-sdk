import Foundation

private struct MiaMoreSubscriptionStatusErrorResponse: Decodable {
  let error: String?
}

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

    let decoder = JSONDecoder()
    MiaMoreHTTP.decodeISODate(decoder)

    if http.statusCode == 404,
       let errorResponse = try? JSONDecoder().decode(MiaMoreSubscriptionStatusErrorResponse.self, from: data),
       errorResponse.error == "not_linked" {
      return MiaMoreSubscriptionStatus(
        isActive: false,
        expiresAt: nil,
        environment: cfg.environment,
        originalTransactionId: "",
        source: nil,
        provider: nil,
        providerAccountId: nil,
        providerChannelId: nil,
        providerCustomerId: nil,
        providerSubscriptionId: nil,
        currentSubscriptionStatus: nil,
        productId: nil,
        priceId: nil,
        entitlementId: nil,
        trialType: nil,
        billingPlanType: nil,
        commitment: nil,
        updatedAt: nil
      )
    }

    if http.statusCode >= 300 {
      let body = String(data: data, encoding: .utf8)
      throw SDKError.httpError(status: http.statusCode, body: body)
    }

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
      "appAccountToken": cfg.appAccountToken.uuidString,
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
