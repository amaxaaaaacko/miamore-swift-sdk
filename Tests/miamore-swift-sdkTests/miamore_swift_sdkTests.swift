import Foundation
import Testing
@testable import miamore_swift_sdk

private func decodeStatus(_ json: String) throws -> MiaMoreSubscriptionStatus {
  let decoder = JSONDecoder()
  MiaMoreHTTP.decodeISODate(decoder)
  return try decoder.decode(MiaMoreSubscriptionStatus.self, from: Data(json.utf8))
}

@Test func decodesPaddleWebSubscriptionWithPayerEmail() throws {
  let status = try decodeStatus("""
    {
      "is_active": true,
      "expires_at": "2026-10-28T11:44:12.045Z",
      "environment": "SANDBOX",
      "original_transaction_id": "",
      "source": "web",
      "provider": "paddle",
      "provider_customer_id": "ctm_01m5f46kva59gdsahm2m4v203j",
      "provider_subscription_id": "sub_01m5f4dbe1r9fcj8njpkazpapr",
      "trial_type": "paid_trial",
      "customer_email": "buyer@example.com",
      "updated_at": null
    }
    """)
  #expect(status.isActive)
  #expect(status.source == .web)
  #expect(status.provider == .paddle)
  #expect(status.customerEmail == "buyer@example.com")
}

@Test func olderBackendResponseWithoutEmailStillDecodes() throws {
  let status = try decodeStatus("""
    { "is_active": false, "environment": "PROD", "original_transaction_id": "", "provider": "some_future_provider" }
    """)
  #expect(status.customerEmail == nil)
  #expect(status.provider == .unknown)
}

/// Answers MiaMore SDK requests from canned responses keyed by path, and records the requests.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
  nonisolated(unsafe) static var requests: [(path: String, body: [String: Any])] = []
  /// `configure()` fires a background `appOpen`; tests only look at the calls under test.
  static var claimFlow: [(path: String, body: [String: Any])] { requests.filter { $0.path != "/v1/sdk/appOpen" } }

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.miamore.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    var bodyData = request.httpBody
    if bodyData == nil, let stream = request.httpBodyStream {
      stream.open()
      var data = Data()
      var buf = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let n = stream.read(&buf, maxLength: buf.count)
        if n <= 0 { break }
        data.append(buf, count: n)
      }
      stream.close()
      bodyData = data
    }
    let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    Self.requests.append((path, body))
    let (code, json) = Self.responses[path] ?? (404, "{}")
    let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct ClaimWebPurchaseTests {
  init() {
    URLProtocol.registerClass(StubURLProtocol.self)
    StubURLProtocol.requests = []
    MiaMoreSDK.configure(
      baseURL: URL(string: "https://stub.miamore.test")!,
      bundleId: "com.example.app",
      apiKey: "sdk_key",
      customerUserId: "device-1",
      appAccountToken: UUID()
    )
  }

  @Test func claimSendsTheEmailThenReturnsTheRefreshedStatus() async throws {
    StubURLProtocol.responses = [
      "/v1/sdk/webClaim": (200, #"{"ok":true,"found":true,"is_active":true}"#),
      "/v1/sdk/subscriptionStatus": (200, #"{"is_active":true,"environment":"PROD","original_transaction_id":"","source":"web","provider":"paddle","customer_email":"buyer@example.com"}"#),
    ]

    let result = try await MiaMoreSDK.claimWebPurchase(email: "Buyer@Example.com")

    #expect(result.found)
    #expect(result.status.isActive)
    #expect(result.status.customerEmail == "buyer@example.com")
    #expect(StubURLProtocol.claimFlow.map(\.path) == ["/v1/sdk/webClaim", "/v1/sdk/subscriptionStatus"])
    let claimBody = StubURLProtocol.claimFlow[0].body
    #expect(claimBody["email"] as? String == "Buyer@Example.com")
    #expect(claimBody["customerUserId"] as? String == "device-1")
    #expect(claimBody["bundleId"] as? String == "com.example.app")
  }

  @Test func anInvalidEmailThrowsTheBackendError() async throws {
    StubURLProtocol.responses = ["/v1/sdk/webClaim": (400, #"{"error":"invalid_email"}"#)]

    await #expect(throws: MiaMoreSDK.SDKError.self) {
      _ = try await MiaMoreSDK.claimWebPurchase(email: "not-an-email")
    }
    #expect(StubURLProtocol.claimFlow.map(\.path) == ["/v1/sdk/webClaim"])
  }
}
