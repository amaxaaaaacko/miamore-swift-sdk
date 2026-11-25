import Foundation
import Testing
@testable import miamore_swift_sdk

private func decodeStatus(_ json: String) throws -> MiaMoreSubscriptionStatus {
  let decoder = JSONDecoder()
  MiaMoreHTTP.decodeISODate(decoder)
  return try decoder.decode(MiaMoreSubscriptionStatus.self, from: Data(json.utf8))
}

private func decodeBillingPlan(_ raw: String) throws -> MiaMoreSDK.BillingPlanType {
  try JSONDecoder().decode(MiaMoreSDK.BillingPlanType.self, from: Data("\"\(raw)\"".utf8))
}

@Suite struct SubscriptionStatusDecodingTests {
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
    #expect(status.updatedAt == nil)
  }

  @Test func olderBackendResponseWithoutEmailStillDecodes() throws {
    let status = try decodeStatus("""
      { "is_active": false, "environment": "PROD", "original_transaction_id": "", "provider": "some_future_provider" }
      """)
    #expect(status.customerEmail == nil)
    #expect(status.provider == .unknown)
  }

  @Test func decodesDatesWithAndWithoutFractionalSeconds() throws {
    let status = try decodeStatus("""
      {
        "is_active": true, "environment": "PROD", "original_transaction_id": "1000",
        "expires_at": "2026-01-02T03:04:05.678Z",
        "updated_at": "2026-01-02T03:04:05Z"
      }
      """)
    let expiresAt = try #require(status.expiresAt)
    let updatedAt = try #require(status.updatedAt)
    #expect(abs(expiresAt.timeIntervalSince(updatedAt) - 0.678) < 0.001)
  }

  @Test func malformedDateFailsTheWholeStatus() {
    #expect(throws: DecodingError.self) {
      _ = try decodeStatus("""
        { "is_active": true, "environment": "PROD", "original_transaction_id": "", "expires_at": "tomorrow" }
        """)
    }
  }

  /// Current behavior: `MiaMoreEnvironment` has no lenient decoding, so a new backend value breaks the status.
  @Test func unknownEnvironmentFailsTheWholeStatus() {
    #expect(throws: DecodingError.self) {
      _ = try decodeStatus(#"{ "is_active": true, "environment": "STAGING", "original_transaction_id": "" }"#)
    }
  }

  /// Current behavior: `environment` and `original_transaction_id` are required.
  @Test func missingEnvironmentFailsTheWholeStatus() {
    #expect(throws: DecodingError.self) {
      _ = try decodeStatus(#"{ "is_active": true, "original_transaction_id": "" }"#)
    }
  }

  /// Current behavior: unlike `provider`, an unknown `source` is not mapped to `.unknown`.
  @Test func unknownSourceFailsTheWholeStatus() {
    #expect(throws: DecodingError.self) {
      _ = try decodeStatus(#"{ "is_active": true, "environment": "PROD", "original_transaction_id": "", "source": "huawei" }"#)
    }
  }

  @Test func decodesCommitmentAndBillingPlan() throws {
    let status = try decodeStatus("""
      {
        "is_active": true, "environment": "PROD", "original_transaction_id": "1000",
        "billing_plan_type": "monthly",
        "commitment": {
          "expiration_date": "2027-01-01T00:00:00Z",
          "billing_period_number": 3,
          "total_billing_periods": 12,
          "total_price": "119.88",
          "auto_renew_status": "on"
        }
      }
      """)
    #expect(status.billingPlanType == .monthlyCommitment)
    #expect(status.commitment?.billingPeriodNumber == 3)
    #expect(status.commitment?.totalBillingPeriods == 12)
    #expect(status.commitment?.expirationDate != nil)
  }
}

@Suite struct BillingPlanTypeDecodingTests {
  @Test(arguments: ["up_front", "upfront", "billed_upfront", "billed-upfront", " UP_FRONT "])
  func upFrontAliases(raw: String) throws {
    #expect(try decodeBillingPlan(raw) == .upFront)
  }

  @Test(arguments: ["monthly", "monthly_commitment", "monthly-commitment", "Monthly"])
  func monthlyCommitmentAliases(raw: String) throws {
    #expect(try decodeBillingPlan(raw) == .monthlyCommitment)
  }

  @Test func unknownValueMapsToUnknown() throws {
    #expect(try decodeBillingPlan("yearly") == .unknown)
  }

  @Test func encodesCanonicalRawValue() throws {
    let data = try JSONEncoder().encode([MiaMoreSDK.BillingPlanType.monthlyCommitment])
    #expect(String(decoding: data, as: UTF8.self) == #"["monthly"]"#)
  }
}

@Suite struct PaymentProviderDecodingTests {
  @Test func decodingIsCaseAndWhitespaceInsensitive() throws {
    let provider = try JSONDecoder().decode(MiaMorePaymentProvider.self, from: Data(#"" Stripe ""#.utf8))
    #expect(provider == .stripe)
  }
}
