import Foundation

public enum MiaMoreEnvironment: String, Codable, Sendable {
  case prod = "PROD"
  case sandbox = "SANDBOX"
  case unknown = "UNKNOWN"
}

public enum MiaMoreSubscriptionSource: String, Codable, Sendable {
  case appStore = "app_store"
  case web = "web"
  case unknown = "unknown"
}

public enum MiaMorePaymentProvider: String, Codable, Sendable {
  case stripe
  case solidgate
  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch raw {
    case "stripe": self = .stripe
    case "solidgate": self = .solidgate
    default: self = .unknown
    }
  }
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
  /// Present for App Store subscriptions. Empty for web-only subscriptions on older backend responses.
  public let originalTransactionId: String
  /// Entitlement source selected by backend. `nil` means older backend response.
  public let source: MiaMoreSubscriptionSource?
  /// Web payment provider when `source == .web`.
  public let provider: MiaMorePaymentProvider?
  public let providerAccountId: String?
  public let providerChannelId: String?
  public let providerCustomerId: String?
  public let providerSubscriptionId: String?
  public let currentSubscriptionStatus: String?
  public let productId: String?
  public let priceId: String?
  public let entitlementId: String?
  public let trialType: String?
  public let billingPlanType: MiaMoreSDK.BillingPlanType?
  public let commitment: Commitment?
  public let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
    case expiresAt = "expires_at"
    case environment
    case originalTransactionId = "original_transaction_id"
    case source
    case provider
    case providerAccountId = "provider_account_id"
    case providerChannelId = "provider_channel_id"
    case providerCustomerId = "provider_customer_id"
    case providerSubscriptionId = "provider_subscription_id"
    case currentSubscriptionStatus = "current_subscription_status"
    case productId = "product_id"
    case priceId = "price_id"
    case entitlementId = "entitlement_id"
    case trialType = "trial_type"
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
