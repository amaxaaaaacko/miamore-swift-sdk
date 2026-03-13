import Foundation

extension MiaMoreSDK {
  /// Store AppsFlyer id (if you want it separately from customerUserId)
  public static func setIntegrationIdentifier(appsflyerId: String) async throws {
    try await updateAttribution(
      appsflyerId: appsflyerId,
      payload: MiaMoreAttributionPayload(raw: [:])
    )
  }

  /// Send attribution payload to MiaMore backend.
  public static func updateAttribution(appsflyerId: String? = nil, payload: MiaMoreAttributionPayload?) async throws {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(baseURL: cfg.baseURL, path: "/v1/sdk/attribution", query: [])

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    var body: [String: Any] = [
      "bundleId": cfg.bundleId,
      "customerUserId": cfg.customerUserId,
    ]

    if let appsflyerId {
      body["appsflyerId"] = appsflyerId
    }

    if let payload {
      let d = try payload.toJSONData()
      body["payload"] = try JSONSerialization.jsonObject(with: d, options: [])
    }

    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw SDKError.invalidResponse }

    if http.statusCode >= 300 {
      let bodyStr = String(data: data, encoding: .utf8)
      throw SDKError.httpError(status: http.statusCode, body: bodyStr)
    }
  }
}
