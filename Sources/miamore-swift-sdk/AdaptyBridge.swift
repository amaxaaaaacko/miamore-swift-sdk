import Foundation

#if canImport(Adapty)
import Adapty

public enum MiaMoreAdaptyBridge {
  /// Call this after you have the AppsFlyer customer_user_id.
  /// This keeps Adapty + AppsFlyer identities aligned.
  public static func identify(customerUserId: String) async throws {
    // Adapty SDK API varies by version. Most versions support identify.
    try await Adapty.identify(customerUserId)
  }
}
#endif
