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
