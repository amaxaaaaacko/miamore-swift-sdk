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
  public let isActive: Bool
  public let expiresAt: Date?
  public let environment: MiaMoreEnvironment?
  public let originalTransactionId: String?
  public let productId: String?
  public let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
    case expiresAt = "expires_at"
    case environment
    case originalTransactionId = "original_transaction_id"
    case productId = "product_id"
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
