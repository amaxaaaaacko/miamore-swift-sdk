import Foundation

public enum MiaMoreEnvironment: String, Codable, Sendable {
  case prod = "PROD"
  case sandbox = "SANDBOX"
}

public enum MiaMoreLogLevel: String, Codable, Sendable {
  case debug
  case info
  case warn
  case error
  case none
}

public struct MiaMoreSubscriptionStatus: Codable, Sendable {
  public struct Commitment: Codable, Sendable {
    public let expirationDate: Date?
    public let billingPeriodNumber: Int?
    public let totalBillingPeriods: Int?
    public let totalPrice: String?
    public let autoRenewStatus: String?

    enum CodingKeys: String, CodingKey {
      case expirationDate = "expiration_date"
      case billingPeriodNumber = "billing_period_number"
      case totalBillingPeriods = "total_billing_periods"
      case totalPrice = "total_price"
      case autoRenewStatus = "auto_renew_status"
    }
  }

  public let isActive: Bool
  public let expiresAt: Date?
  public let environment: MiaMoreEnvironment
  public let originalTransactionId: String
  public let currentSubscriptionStatus: String?
  public let productId: String?
  public let billingPlanType: MiaMoreSDK.BillingPlanType?
  public let commitment: Commitment?
  public let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
    case expiresAt = "expires_at"
    case environment
    case originalTransactionId = "original_transaction_id"
    case currentSubscriptionStatus = "current_subscription_status"
    case productId = "product_id"
    case billingPlanType = "billing_plan_type"
    case commitment
    case updatedAt = "updated_at"
  }
}

public struct MiaMoreAttributionPayload: @unchecked Sendable {
  public let raw: [String: Any]

  public init(raw: [String: Any]) {
    self.raw = raw
  }

  public func toJSONData() throws -> Data {
    try JSONSerialization.data(withJSONObject: raw, options: [])
  }
}
