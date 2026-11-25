import Foundation
import Testing
@testable import miamore_swift_sdk

/// Characterization tests for the shape of every backend request.
///
/// `MiaMoreSDK` keeps its configuration in a static and `StubURLProtocol` records into a static,
/// so every suite touching the network is nested here to run serially.
@MainActor @Suite(.serialized) struct BackendRequestTests {
  private static let jsonContentType = "application/json"
  private static let bearer = "Bearer \(StubbedSDK.apiKey)"

  private static func expectJSONPost(_ request: RecordedRequest) {
    #expect(request.method == "POST")
    #expect(request.headers["Authorization"] == bearer)
    #expect(request.headers["Content-Type"] == jsonContentType)
    #expect(request.headers["Accept"] == jsonContentType)
  }

  private static func expectGet(_ request: RecordedRequest) {
    #expect(request.method == "GET")
    #expect(request.headers["Authorization"] == bearer)
    #expect(request.headers["Accept"] == jsonContentType)
  }

  // MARK: - Paywall

  @MainActor @Suite struct Paywall {
    private static let path = "/v1/sdk/paywall"
    private static let response = """
      {
        "app_bundle_id": "com.example.app",
        "customer_user_id": "device-1",
        "placement": "onboarding",
        "assignment": { "experiment_id": "exp_1", "variant_id": "b", "bucket": 42 },
        "paywall": {
          "paywall_id": "pw_1",
          "name": "Main",
          "products": [
            { "product_id": "com.example.year", "sort": 1, "billing_plan_type": "monthly" },
            { "product_id": "com.example.week" }
          ]
        }
      }
      """

    init() {
      StubbedSDK.configure(responses: [Self.path: (200, Self.response)])
    }

    @Test func placementRequestSendsIdentityAndDecodesThePaywall() async throws {
      let result = try await MiaMoreSDK.getPaywall(placement: "onboarding")

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      BackendRequestTests.expectGet(request)
      #expect(request.path == Self.path)
      #expect(request.query == [
        "bundleId": StubbedSDK.bundleId,
        "customerUserId": StubbedSDK.customerUserId,
        "placement": "onboarding",
      ])
      #expect(result.paywall.paywallId == "pw_1")
      #expect(result.assignment?.bucket == 42)
      #expect(result.paywall.products.map(\.productId) == ["com.example.year", "com.example.week"])
      #expect(result.paywall.products[0].billingPlanType == .monthlyCommitment)
      #expect(result.paywall.products[1].billingPlanType == nil)
      #expect(result.paywall.products[1].sort == nil)
    }

    @Test func nilAndEmptySelectorsAreLeftOutOfTheQuery() async throws {
      _ = try await MiaMoreSDK.getPaywall(placement: "", paywallId: "pw_1", experimentId: nil)

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      #expect(request.query == [
        "bundleId": StubbedSDK.bundleId,
        "customerUserId": StubbedSDK.customerUserId,
        "paywallId": "pw_1",
      ])
    }

    @Test func non2xxThrowsHTTPErrorWithTheBody() async throws {
      StubURLProtocol.install(responses: [Self.path: (500, #"{"error":"boom"}"#)])

      let error = await #expect(throws: MiaMoreSDK.SDKError.self) {
        _ = try await MiaMoreSDK.getPaywall(placement: "onboarding")
      }
      guard case .httpError(let status, let body) = error else {
        Issue.record("Expected httpError, got \(String(describing: error))")
        return
      }
      #expect(status == 500)
      #expect(body == #"{"error":"boom"}"#)
    }
  }

  // MARK: - Link

  @MainActor @Suite struct Link {
    private static let path = "/v1/sdk/link"

    @Test func sendsTransactionWithConfiguredEnvironmentAndToken() async throws {
      StubbedSDK.configure(environment: .sandbox, responses: [Self.path: (200, "{}")])

      try await MiaMoreSDK.link(originalTransactionId: "2000000123")

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      BackendRequestTests.expectJSONPost(request)
      #expect(request.path == Self.path)
      #expect(request.body as? [String: String] == [
        "bundleId": StubbedSDK.bundleId,
        "customerUserId": StubbedSDK.customerUserId,
        "appAccountToken": StubbedSDK.appAccountToken.uuidString,
        "environment": "SANDBOX",
        "originalTransactionId": "2000000123",
      ])
    }

    @Test func explicitEnvironmentOverridesTheConfiguredOne() async throws {
      StubbedSDK.configure(environment: .prod, responses: [Self.path: (200, "{}")])

      try await MiaMoreSDK.link(originalTransactionId: "1", environment: .sandbox)

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      #expect(request.body["environment"] as? String == "SANDBOX")
    }

    @Test func non2xxThrows() async throws {
      StubbedSDK.configure(responses: [Self.path: (409, #"{"error":"conflict"}"#)])

      await #expect(throws: MiaMoreSDK.SDKError.self) {
        try await MiaMoreSDK.link(originalTransactionId: "1")
      }
    }
  }

  // MARK: - Attribution

  @MainActor @Suite struct Attribution {
    private static let path = "/v1/sdk/attribution"

    init() {
      StubbedSDK.configure(responses: [Self.path: (200, "{}")])
    }

    @Test func sendsAppsFlyerIdAndNestedPayload() async throws {
      let payload = MiaMoreAttributionPayload(raw: ["media_source": "tiktok", "is_first_launch": true])

      try await MiaMoreSDK.updateAttribution(appsflyerId: "af-1", payload: payload)

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      BackendRequestTests.expectJSONPost(request)
      #expect(request.path == Self.path)
      #expect(Set(request.body.keys) == ["bundleId", "customerUserId", "appsflyerId", "payload"])
      #expect(request.body["appsflyerId"] as? String == "af-1")
      let sentPayload = try #require(request.body["payload"] as? [String: Any])
      #expect(sentPayload["media_source"] as? String == "tiktok")
      #expect(sentPayload["is_first_launch"] as? Bool == true)
    }

    @Test func firebaseIdentifierSendsOnlyThatId() async throws {
      try await MiaMoreSDK.setIntegrationIdentifier(firebaseAppInstanceId: "fb-1")

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      #expect(request.body as? [String: String] == [
        "bundleId": StubbedSDK.bundleId,
        "customerUserId": StubbedSDK.customerUserId,
        "firebaseAppInstanceId": "fb-1",
      ])
    }

    @Test func appsFlyerIdentifierSendsOnlyThatId() async throws {
      try await MiaMoreSDK.setIntegrationIdentifier(appsflyerId: "af-2")

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      #expect(Set(request.body.keys) == ["bundleId", "customerUserId", "appsflyerId"])
    }
  }

  // MARK: - App open

  @MainActor @Suite struct AppOpen {
    init() {
      StubbedSDK.configure(responses: [StubURLProtocol.appOpenPath: (200, "{}")])
    }

    /// The auto tracker may send its own `appOpen` at any moment; it has the same shape, so every one is checked.
    @Test func sendsIdentityTimestampAndTimezoneOffset() async throws {
      try await MiaMoreSDK.trackAppOpen()

      let requests = StubURLProtocol.requests.filter { $0.path == StubURLProtocol.appOpenPath }
      #expect(!requests.isEmpty)
      for request in requests {
        BackendRequestTests.expectJSONPost(request)
        #expect(Set(request.body.keys) == ["bundleId", "customerUserId", "openedAt", "tzOffsetMin"])
        #expect(request.body["bundleId"] as? String == StubbedSDK.bundleId)
        #expect(request.body["customerUserId"] as? String == StubbedSDK.customerUserId)
        #expect(request.body["tzOffsetMin"] as? Int == TimeZone.current.secondsFromGMT() / 60)
        let openedAt = try #require(request.body["openedAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: openedAt) != nil)
      }
    }
  }

  // MARK: - Subscription status

  @MainActor @Suite struct SubscriptionStatus {
    private static let path = "/v1/sdk/subscriptionStatus"

    @Test func sendsIdentityAndDecodesTheStatus() async throws {
      StubbedSDK.configure(responses: [
        Self.path: (200, #"{"is_active":true,"environment":"PROD","original_transaction_id":"1000","source":"app_store"}"#),
      ])

      let status = try await MiaMoreSDK.getSubscriptionStatus()

      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      BackendRequestTests.expectGet(request)
      #expect(request.query == ["bundleId": StubbedSDK.bundleId, "customerUserId": StubbedSDK.customerUserId])
      #expect(status.isActive)
      #expect(status.source == .appStore)
      #expect(status.originalTransactionId == "1000")
    }

    @Test func notLinkedIsAnInactiveStatusInTheConfiguredEnvironment() async throws {
      StubbedSDK.configure(environment: .sandbox, responses: [Self.path: (404, #"{"error":"not_linked"}"#)])

      let status = try await MiaMoreSDK.getSubscriptionStatus()

      #expect(!status.isActive)
      #expect(status.environment == .sandbox)
      #expect(status.originalTransactionId == "")
      #expect(status.source == nil)
      #expect(status.expiresAt == nil)
    }

    @Test func other404Throws() async throws {
      StubbedSDK.configure(responses: [Self.path: (404, #"{"error":"app_not_found"}"#)])

      let error = await #expect(throws: MiaMoreSDK.SDKError.self) {
        _ = try await MiaMoreSDK.getSubscriptionStatus()
      }
      guard case .httpError(let status, _) = error else {
        Issue.record("Expected httpError, got \(String(describing: error))")
        return
      }
      #expect(status == 404)
    }
  }

  // MARK: - Web claim

  @MainActor @Suite struct ClaimWebPurchase {
    init() {
      StubbedSDK.configure()
    }

    @Test func claimSendsTheEmailThenReturnsTheRefreshedStatus() async throws {
      StubURLProtocol.install(responses: [
        "/v1/sdk/webClaim": (200, #"{"ok":true,"found":true,"is_active":true}"#),
        "/v1/sdk/subscriptionStatus": (200, #"{"is_active":true,"environment":"PROD","original_transaction_id":"","source":"web","provider":"paddle","customer_email":"buyer@example.com"}"#),
      ])

      let result = try await MiaMoreSDK.claimWebPurchase(email: "Buyer@Example.com")

      #expect(result.found)
      #expect(result.status.isActive)
      #expect(result.status.customerEmail == "buyer@example.com")
      let requests = StubURLProtocol.requestsExceptAppOpen
      #expect(requests.map(\.path) == ["/v1/sdk/webClaim", "/v1/sdk/subscriptionStatus"])
      BackendRequestTests.expectJSONPost(requests[0])
      #expect(requests[0].body as? [String: String] == [
        "bundleId": StubbedSDK.bundleId,
        "customerUserId": StubbedSDK.customerUserId,
        "email": "Buyer@Example.com",
      ])
    }

    @Test func missingFoundFlagMeansNotFound() async throws {
      StubURLProtocol.install(responses: [
        "/v1/sdk/webClaim": (200, "{}"),
        "/v1/sdk/subscriptionStatus": (404, #"{"error":"not_linked"}"#),
      ])

      let result = try await MiaMoreSDK.claimWebPurchase(email: "nobody@example.com")

      #expect(!result.found)
      #expect(!result.status.isActive)
    }

    @Test func anInvalidEmailThrowsTheBackendError() async throws {
      StubURLProtocol.install(responses: ["/v1/sdk/webClaim": (400, #"{"error":"invalid_email"}"#)])

      await #expect(throws: MiaMoreSDK.SDKError.self) {
        _ = try await MiaMoreSDK.claimWebPurchase(email: "not-an-email")
      }
      #expect(StubURLProtocol.requestsExceptAppOpen.map(\.path) == ["/v1/sdk/webClaim"])
    }
  }
}
